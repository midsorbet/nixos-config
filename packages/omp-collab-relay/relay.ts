/**
 * Hardened loopback relay for OMP collab (`/collab wss://…`).
 *
 * Speaks the exact relay contract OMP clients expect, mirroring the upstream
 * reference relay (oh-my-pi `packages/collab-web/scripts/local-relay.ts`,
 * v16.3.2):
 *
 * - `GET /r/<roomId>?role=host|guest` upgrades to a WebSocket.
 * - The host creates the room; a second host is rejected with close 4009 and
 *   a guest joining a missing room with close 4004.
 * - Host binary frames: envelope peerId 0 broadcasts to every guest, peerId N
 *   targets that guest only — forwarded unchanged either way.
 * - Guest binary frames: the first 4 envelope bytes (big-endian uint32) are
 *   rewritten to the sender's peerId, then forwarded to the host.
 * - TEXT control to the host: `{"t":"peer-joined","peer":N}` /
 *   `{"t":"peer-left","peer":N}`.
 * - Host disconnect: TEXT `{"t":"room-closed"}` to every guest, then close
 *   4001 and the room is garbage-collected.
 *
 * Hardening for on-demand public exposure through a Cloudflare Quick Tunnel:
 *
 * - binds to loopback only (`--bind` accepts loopback addresses exclusively);
 * - `GET /healthz` liveness endpoint;
 * - one room and a small socket budget by default; extra rooms/sockets get
 *   fatal close 4029 ("room is full"), which OMP clients treat as terminal —
 *   no reconnect storms (see `coding-agent/src/collab/relay-client.ts`
 *   FATAL_CLOSE_REASONS);
 * - one guest per room by default, closed with NON-fatal 4030 ("room is
 *   full, try again later") instead: only link holders can reach an
 *   existing room, and a legitimate guest reconnecting past its own
 *   not-yet-reaped stale socket must not be permanently kicked — its
 *   retries are bounded by client backoff. App-range 4xxx because proxies
 *   rewrite reserved codes like 1013 to an abnormal 1006;
 * - bounded frame size, enforced in message() so close codes stay coherent:
 *   a host offender tears the room down (4001 both ways) instead of
 *   silently reconnecting into an empty room, a guest offender gets
 *   non-fatal 4013;
 * - idle rooms are torn down with fatal close 4001 after a quiet period.
 *   Deliberate: liveness never counts as activity, so a quiet-but-live
 *   session ends at the timeout — raise --idle-timeout-secs for long
 *   passive sessions;
 * - logs carry truncated room ids only — never paths, query strings, or link
 *   material. Session payloads stay sealed end to end (AES-256-GCM).
 *
 * Cloudflare Quick Tunnel caveat (measured 2026-07-03): close codes issued
 * DURING open() — the 4004/4009/4029/4030 rejections — race the upgrade in
 * the cloudflared/edge pipeline and can surface to the remote client as an
 * abnormal 1006. That degrades intended-fatal rejections to non-fatal
 * backoff retries through the tunnel, which is acceptable here: retries are
 * bounded (max 30s interval), rejections re-apply, and a reconnecting stale
 * host actually recovers. Codes sent on established sockets (room-closed
 * 4001, idle teardown, frame-cap teardown) traverse the tunnel intact.
 * Direct/local connections always see the exact codes.
 *
 * Not implemented (terminal-only v1): `GET /` collab-web browser client and
 * the `/s` (`/share`) blob routes. Guests must join from a terminal.
 */

import type { RelayControlToGuest, RelayControlToHost } from "@oh-my-pi/pi-wire";
import { ENVELOPE_HEADER_LENGTH } from "@oh-my-pi/pi-wire";

/**
 * Relay-side room path. Upstream does not publish this (it lives in the
 * private collab-web package and coding-agent protocol.ts); exported so the
 * conformance tests can assert it accepts upstream-sized room ids.
 */
export const ROOM_PATH_RE = /^\/r\/([A-Za-z0-9_-]{10,64})$/;

export interface RelayOptions {
	port: number;
	bind: string;
	maxRooms: number;
	maxGuestsPerRoom: number;
	maxSockets: number;
	maxFrameBytes: number;
	idleTimeoutSecs: number;
	/** Suppress logging (tests). */
	quiet: boolean;
}

export const DEFAULT_OPTIONS: RelayOptions = {
	port: 7475,
	bind: "127.0.0.1",
	maxRooms: 1,
	maxGuestsPerRoom: 1,
	maxSockets: 8,
	maxFrameBytes: 16 * 1024 * 1024,
	idleTimeoutSecs: 1800,
	quiet: false,
};

interface SocketData {
	roomId: string;
	role: "host" | "guest";
	/** Assigned on open for guests; the host stays 0. */
	peerId: number;
}

type RelaySocket = Bun.ServerWebSocket<SocketData>;

interface Room {
	host: RelaySocket;
	guests: Map<number, RelaySocket>;
	nextPeerId: number;
	lastActivityMs: number;
}

export interface CollabRelay {
	/** ws://127.0.0.1:<port> — append `/r/<roomId>?role=…` to connect. */
	url: string;
	port: number;
	/** Closes every room and stops the server. Idempotent. */
	stop(): void;
}

function isLoopbackBind(host: string): boolean {
	if (host === "localhost" || host === "::1") return true;
	if (!/^127(?:\.\d{1,3}){3}$/.test(host)) return false;
	return host.split(".").every(octet => Number(octet) <= 255);
}

export function startRelay(overrides: Partial<RelayOptions> = {}): CollabRelay {
	const opts: RelayOptions = { ...DEFAULT_OPTIONS, ...overrides };
	if (!isLoopbackBind(opts.bind)) {
		throw new Error(`refusing to bind non-loopback address ${opts.bind}`);
	}

	const rooms = new Map<string, Room>();
	let openSockets = 0;

	const log = (message: string): void => {
		if (!opts.quiet) console.log(`[omp-collab-relay] ${message}`);
	};
	/** Truncated id for logs: enough to correlate, never the full path segment. */
	const roomTag = (roomId: string): string => `${roomId.slice(0, 8)}…`;

	/** Tear a room down: room-closed + fatal 4001 to guests, `hostCode` to the host. */
	const closeRoom = (roomId: string, room: Room, hostCode: number, hostReason: string): void => {
		rooms.delete(roomId);
		const closure = JSON.stringify({ t: "room-closed" } satisfies RelayControlToGuest);
		for (const guest of room.guests.values()) {
			guest.send(closure);
			guest.close(4001, "room closed");
		}
		room.guests.clear();
		room.host.close(hostCode, hostReason);
	};

	const server = Bun.serve<SocketData>({
		hostname: opts.bind,
		port: opts.port,
		fetch(req, srv): Response | undefined {
			const url = new URL(req.url);
			if (url.pathname === "/healthz") return new Response("ok\n");
			const match = ROOM_PATH_RE.exec(url.pathname);
			const role = url.searchParams.get("role");
			if (!match || (role !== "host" && role !== "guest")) {
				return new Response("not found", { status: 404 });
			}
			const data: SocketData = { roomId: match[1]!, role, peerId: 0 };
			if (srv.upgrade(req, { data })) return undefined;
			return new Response("websocket upgrade required", { status: 426 });
		},
		websocket: {
			// Protocol ceiling: the configured cap is enforced in message() for
			// coherent close codes; frames beyond this ceiling are protocol-closed
			// by Bun exactly like the upstream relay (16 MiB Bun default). The
			// ceiling deliberately does NOT rise above the cap — that would only
			// grow attacker-controllable frame buffering on a hardened relay.
			maxPayloadLength: Math.max(opts.maxFrameBytes, DEFAULT_OPTIONS.maxFrameBytes),
			open(ws: RelaySocket): void {
				openSockets++;
				const { roomId, role } = ws.data;
				// Cap total sockets with fatal 4029 — OMP clients treat it as
				// terminal, so over-capacity peers don't retry-loop (an HTTP 503
				// before upgrade would read as a transient handshake failure).
				if (openSockets > opts.maxSockets) {
					log(`rejected ${role}: socket limit ${opts.maxSockets} reached`);
					ws.close(4029, "relay is at its socket limit");
					return;
				}
				if (role === "host") {
					if (rooms.has(roomId)) {
						ws.close(4009, "a host is already connected for this room");
						return;
					}
					if (rooms.size >= opts.maxRooms) {
						log(`rejected host: room limit ${opts.maxRooms} reached`);
						ws.close(4029, "room is full");
						return;
					}
					rooms.set(roomId, { host: ws, guests: new Map(), nextPeerId: 1, lastActivityMs: Date.now() });
					log(`host connected, room ${roomTag(roomId)} open (rooms=${rooms.size}, sockets=${openSockets})`);
					return;
				}
				const room = rooms.get(roomId);
				if (!room) {
					ws.close(4004, "no such room");
					return;
				}
				if (room.guests.size >= opts.maxGuestsPerRoom) {
					log(`rejected guest: room ${roomTag(roomId)} is full`);
					ws.close(4030, "room is full, try again later");
					return;
				}
				const peerId = room.nextPeerId++;
				ws.data.peerId = peerId;
				room.guests.set(peerId, ws);
				room.lastActivityMs = Date.now();
				room.host.send(JSON.stringify({ t: "peer-joined", peer: peerId } satisfies RelayControlToHost));
				log(`guest ${peerId} joined room ${roomTag(roomId)} (guests=${room.guests.size}, sockets=${openSockets})`);
			},
			message(ws: RelaySocket, message: string | Buffer): void {
				if (typeof message === "string") return; // clients never send TEXT
				if (message.byteLength < ENVELOPE_HEADER_LENGTH) return;
				const room = rooms.get(ws.data.roomId);
				if (!room) return;
				// Enforce the configured frame cap here, where close codes are
				// coherent (maxPayloadLength above is only the protocol ceiling):
				// a host offender killed at the protocol layer would reconnect
				// into an empty room while its guests were fatally closed — a
				// silent split-brain.
				if (message.byteLength > opts.maxFrameBytes) {
					if (ws.data.role === "host" && room.host === ws) {
						log(`host frame of ${message.byteLength}B exceeds cap ${opts.maxFrameBytes}B, closing room ${roomTag(ws.data.roomId)}`);
						closeRoom(ws.data.roomId, room, 4001, "frame too large");
					} else {
						log(`closing ${ws.data.role} socket: frame of ${message.byteLength}B exceeds cap ${opts.maxFrameBytes}B`);
						ws.close(4013, "frame too large");
					}
					return;
				}
				if (ws.data.role === "host") {
					// Rejected duplicate host: not this room's host, drop.
					if (room.host !== ws) return;
					room.lastActivityMs = Date.now();
					const peerId = message.readUInt32BE(0);
					if (peerId === 0) {
						for (const guest of room.guests.values()) guest.send(message);
					} else {
						room.guests.get(peerId)?.send(message);
					}
					return;
				}
				// Rejected guests (peerId 0 or unregistered) must not inject frames.
				if (room.guests.get(ws.data.peerId) !== ws) return;
				room.lastActivityMs = Date.now();
				message.writeUInt32BE(ws.data.peerId, 0);
				room.host.send(message);
			},
			close(ws: RelaySocket): void {
				openSockets = Math.max(0, openSockets - 1);
				const { roomId, role, peerId } = ws.data;
				const room = rooms.get(roomId);
				if (!room) return;
				if (role === "host") {
					// Rejected second host: the live room is not ours to tear down.
					if (room.host !== ws) return;
					rooms.delete(roomId);
					const closure = JSON.stringify({ t: "room-closed" } satisfies RelayControlToGuest);
					for (const guest of room.guests.values()) {
						guest.send(closure);
						guest.close(4001, "room closed");
					}
					room.guests.clear();
					log(`host left, room ${roomTag(roomId)} closed (rooms=${rooms.size}, sockets=${openSockets})`);
					return;
				}
				if (room.guests.delete(peerId)) {
					room.lastActivityMs = Date.now();
					room.host.send(JSON.stringify({ t: "peer-left", peer: peerId } satisfies RelayControlToHost));
					log(`guest ${peerId} left room ${roomTag(roomId)} (guests=${room.guests.size}, sockets=${openSockets})`);
				}
			},
		},
	});

	// Idle teardown backstop: sweep at 1/4 of the timeout, clamped to 250ms..30s.
	const sweepMs = Math.min(Math.max(Math.floor(opts.idleTimeoutSecs * 250), 250), 30_000);
	const sweeper = setInterval(() => {
		const cutoff = Date.now() - opts.idleTimeoutSecs * 1000;
		for (const [roomId, room] of rooms) {
			if (room.lastActivityMs > cutoff) continue;
			log(`room ${roomTag(roomId)} idle for ${opts.idleTimeoutSecs}s, closing`);
			// Fatal 4001 both ways so neither side reconnects and re-registers the room.
			closeRoom(roomId, room, 4001, "room closed");
		}
	}, sweepMs);

	const displayHost = opts.bind.includes(":") ? `[${opts.bind}]` : opts.bind;
	log(
		`listening on http://${displayHost}:${server.port} ` +
			`(rooms<=${opts.maxRooms}, guests/room<=${opts.maxGuestsPerRoom}, sockets<=${opts.maxSockets}, ` +
			`frame<=${opts.maxFrameBytes}B, idle=${opts.idleTimeoutSecs}s)`,
	);
	log("terminal-only relay: GET / serves no browser client; /s (share) routes are disabled");

	return {
		url: `ws://${displayHost}:${server.port}`,
		port: server.port,
		stop(): void {
			clearInterval(sweeper);
			for (const [roomId, room] of rooms) {
				closeRoom(roomId, room, 1001, "relay shutting down");
			}
			server.stop(true);
		},
	};
}

const NUMERIC_FLAGS: Record<string, "port" | "maxRooms" | "maxGuestsPerRoom" | "maxSockets" | "maxFrameBytes" | "idleTimeoutSecs"> = {
	"--port": "port",
	"--max-rooms": "maxRooms",
	"--max-guests": "maxGuestsPerRoom",
	"--max-sockets": "maxSockets",
	"--max-frame-bytes": "maxFrameBytes",
	"--idle-timeout-secs": "idleTimeoutSecs",
};

function usage(): string {
	return `usage: omp-collab-relay [options]

Hardened loopback OMP collab relay (terminal-only: no browser client, no /share).

options:
  --port N               listen port (default ${DEFAULT_OPTIONS.port}, 0 = ephemeral)
  --bind ADDR            loopback listen address (default ${DEFAULT_OPTIONS.bind})
  --max-rooms N          concurrent room limit (default ${DEFAULT_OPTIONS.maxRooms})
  --max-guests N         guests per room (default ${DEFAULT_OPTIONS.maxGuestsPerRoom})
  --max-sockets N        total websocket limit (default ${DEFAULT_OPTIONS.maxSockets})
  --max-frame-bytes N    websocket frame cap (default ${DEFAULT_OPTIONS.maxFrameBytes})
  --idle-timeout-secs N  idle room teardown (default ${DEFAULT_OPTIONS.idleTimeoutSecs})
  -h, --help             show this help`;
}

function fail(message: string): never {
	console.error(`omp-collab-relay: ${message}`);
	console.error(usage());
	process.exit(2);
}

function parseArgs(argv: readonly string[]): Partial<RelayOptions> {
	const overrides: Partial<RelayOptions> = {};
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i]!;
		if (arg === "-h" || arg === "--help") {
			console.log(usage());
			process.exit(0);
		}
		const eq = arg.indexOf("=");
		const flag = eq === -1 ? arg : arg.slice(0, eq);
		const rawValue = eq === -1 ? argv[++i] : arg.slice(eq + 1);
		if (flag === "--bind") {
			if (rawValue === undefined) fail("missing value for --bind");
			overrides.bind = rawValue;
			continue;
		}
		const key = NUMERIC_FLAGS[flag];
		if (!key) fail(`unknown argument ${arg}`);
		const value = Number(rawValue);
		if (rawValue === undefined || rawValue === "" || !Number.isInteger(value) || value < 0) {
			fail(`invalid value for ${flag}: ${rawValue === undefined ? "<missing>" : rawValue}`);
		}
		if (key === "port") {
			if (value > 65_535) fail(`invalid value for --port: ${rawValue}`);
		} else if (value < 1) {
			fail(`invalid value for ${flag}: ${rawValue} (must be >= 1)`);
		}
		overrides[key] = value;
	}
	return overrides;
}

if (import.meta.main) {
	const overrides = parseArgs(Bun.argv.slice(2));
	let relay: CollabRelay;
	try {
		relay = startRelay(overrides);
	} catch (err) {
		console.error(`omp-collab-relay: startup failed: ${err instanceof Error ? err.message : String(err)}`);
		process.exit(1);
	}
	let stopping = false;
	const shutdown = (): void => {
		if (stopping) return;
		stopping = true;
		relay.stop();
		process.exit(0);
	};
	process.on("SIGINT", shutdown);
	process.on("SIGTERM", shutdown);
}
