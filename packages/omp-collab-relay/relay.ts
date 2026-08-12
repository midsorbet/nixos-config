import { existsSync, readdirSync, statSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import type {
	RelayControlToGuest,
	RelayControlToHost,
} from "@oh-my-pi/pi-wire";
import { ENVELOPE_HEADER_LENGTH } from "@oh-my-pi/pi-wire";

export const ROOM_PATH_RE = /^\/r\/([A-Za-z0-9_-]{10,64})$/;
const ROOM_LINK_PATH_RE = /^\/r\/([A-Za-z0-9_-]{10,64})\.([A-Za-z0-9_-]+)$/;
const PROTOCOL_MAX_FRAME_BYTES = 16 * 1024 * 1024;

export interface RelayOptions {
	port: number;
	bind: string;
	maxGuestsPerRoom: number;
	maxSockets: number;
	maxFrameBytes: number;
	idleTimeoutSecs: number;
	maxConnectionSecs: number;
	allowedOrigins: readonly string[];
	requireAccessJwt: boolean;
	webRoot: string | null;
	quiet: boolean;
}

export interface RelayCallbacks {
	onIdleTimeout?: () => void;
}

export const DEFAULT_OPTIONS: RelayOptions = {
	port: 17475,
	bind: "127.0.0.1",
	maxGuestsPerRoom: 1,
	maxSockets: 32,
	maxFrameBytes: PROTOCOL_MAX_FRAME_BYTES,
	idleTimeoutSecs: 1800,
	maxConnectionSecs: 1800,
	allowedOrigins: ["https://omp.midsorbet.me"],
	requireAccessJwt: false,
	webRoot: null,
	quiet: false,
};

interface SocketData {
	roomId: string;
	role: "host" | "guest";
	peerId: number;
	connectionLifetimeSecs: number;
	expiryTimer?: Timer;
}

type RelaySocket = Bun.ServerWebSocket<SocketData>;

interface RoomRegistration {
	link: string;
	label: string;
	cwd: string;
}

interface Room {
	host: RelaySocket;
	guests: Map<number, RelaySocket>;
	nextPeerId: number;
	openedAtMs: number;
	lastActivityMs: number;
	registration?: RoomRegistration;
}

export interface CollabRelay {
	url: string;
	port: number;
	stop(): void;
}

function isLoopbackBind(host: string): boolean {
	if (host === "localhost" || host === "::1") return true;
	if (!/^127(?:\.\d{1,3}){3}$/.test(host)) return false;
	return host.split(".").every((octet) => Number(octet) <= 255);
}

function validatePositiveInteger(name: string, value: number): void {
	if (!Number.isInteger(value) || value <= 0)
		throw new Error(`${name} must be a positive integer`);
}

function validateOptions(opts: RelayOptions): void {
	if (!isLoopbackBind(opts.bind))
		throw new Error(`refusing to bind non-loopback address ${opts.bind}`);
	if (!Number.isInteger(opts.port) || opts.port < 0 || opts.port > 65_535)
		throw new Error("port must be between 0 and 65535");
	validatePositiveInteger("maxGuestsPerRoom", opts.maxGuestsPerRoom);
	validatePositiveInteger("maxSockets", opts.maxSockets);
	validatePositiveInteger("maxFrameBytes", opts.maxFrameBytes);
	validatePositiveInteger("idleTimeoutSecs", opts.idleTimeoutSecs);
	validatePositiveInteger("maxConnectionSecs", opts.maxConnectionSecs);
	if (opts.maxFrameBytes > PROTOCOL_MAX_FRAME_BYTES) {
		throw new Error(`maxFrameBytes cannot exceed ${PROTOCOL_MAX_FRAME_BYTES}`);
	}
	for (const origin of opts.allowedOrigins) {
		const parsed = new URL(origin);
		if (parsed.origin !== origin || parsed.protocol !== "https:") {
			throw new Error(`allowed origin must be an https origin: ${origin}`);
		}
	}
	if (opts.webRoot !== null) {
		if (
			!isAbsolute(opts.webRoot) ||
			!existsSync(opts.webRoot) ||
			!statSync(opts.webRoot).isDirectory()
		) {
			throw new Error(
				`webRoot must be an existing absolute directory: ${opts.webRoot}`,
			);
		}
	}
}

function accessTokenLifetimeSecs(token: string | null): number | null {
	if (!token) return null;
	const payload = token.split(".", 3)[1];
	if (!payload) return null;
	try {
		const claims: unknown = JSON.parse(
			Buffer.from(payload, "base64url").toString("utf8"),
		);
		if (
			typeof claims !== "object" ||
			claims === null ||
			!("exp" in claims) ||
			typeof claims.exp !== "number" ||
			!Number.isFinite(claims.exp)
		) {
			return null;
		}
		return Math.max(1, Math.floor(claims.exp - Date.now() / 1000));
	} catch {
		return null;
	}
}

interface StaticAsset {
	path: string;
	contentType: string;
	size: number;
	immutable: boolean;
}

const HASHED_ASSET_RE = /^\/[a-z0-9]{8}\.[a-z0-9]+$/;
const STATIC_CONTENT_SECURITY_POLICY = [
	"base-uri 'none'",
	"connect-src 'self'",
	"default-src 'self'",
	"font-src 'self'",
	"form-action 'none'",
	"frame-ancestors 'none'",
	"img-src 'self' data:",
	"manifest-src 'self'",
	"object-src 'none'",
	"script-src 'self'",
	"style-src 'self' 'unsafe-inline'",
].join("; ");

function loadStaticAssets(
	webRoot: string | null,
): ReadonlyMap<string, StaticAsset> {
	const assets = new Map<string, StaticAsset>();
	if (webRoot === null) return assets;
	for (const name of readdirSync(webRoot)) {
		const path = join(webRoot, name);
		const stat = statSync(path);
		if (!stat.isFile()) continue;
		const route = `/${name}`;
		assets.set(route, {
			path,
			contentType: Bun.file(path).type || "application/octet-stream",
			size: stat.size,
			immutable: HASHED_ASSET_RE.test(route),
		});
	}
	const index = assets.get("/index.html");
	if (!index)
		throw new Error(`webRoot does not contain index.html: ${webRoot}`);
	assets.set("/", index);
	return assets;
}

function serveStatic(
	req: Request,
	pathname: string,
	assets: ReadonlyMap<string, StaticAsset>,
): Response | null {
	if (req.method !== "GET" && req.method !== "HEAD") return null;
	const asset = assets.get(pathname);
	if (!asset) return null;
	const headers = new Headers({
		"Cache-Control":
			pathname === "/"
				? "no-store"
				: asset.immutable
					? "public, max-age=31536000, immutable"
					: "public, max-age=300",
		"Content-Length": String(asset.size),
		"Content-Security-Policy": STATIC_CONTENT_SECURITY_POLICY,
		"Content-Type": asset.contentType,
		"Cross-Origin-Opener-Policy": "same-origin",
		"Cross-Origin-Resource-Policy": "same-origin",
		"Permissions-Policy":
			"camera=(), microphone=(), geolocation=(), payment=(), usb=()",
		"Referrer-Policy": "no-referrer",
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options": "DENY",
	});
	return new Response(req.method === "HEAD" ? null : Bun.file(asset.path), {
		headers,
	});
}

export function startRelay(
	overrides: Partial<RelayOptions> = {},
	callbacks: RelayCallbacks = {},
): CollabRelay {
	const opts: RelayOptions = { ...DEFAULT_OPTIONS, ...overrides };
	validateOptions(opts);

	const allowedOrigins = new Set(opts.allowedOrigins);
	const allowedRelayOrigins = new Set(
		opts.allowedOrigins.map((origin) => origin.replace(/^https:/, "wss:")),
	);
	const staticAssets = loadStaticAssets(opts.webRoot);
	const rooms = new Map<string, Room>();
	let openSockets = 0;
	let lastRelayActivityMs = Date.now();
	let idleNotified = false;
	let stopped = false;
	const log = (message: string): void => {
		if (!opts.quiet) console.log(`[omp-collab-relay] ${message}`);
	};
	const roomTag = (roomId: string): string => `${roomId.slice(0, 8)}…`;

	const noteActivity = (room?: Room): number => {
		const now = Date.now();
		lastRelayActivityMs = now;
		if (room) room.lastActivityMs = now;
		idleNotified = false;
		return now;
	};
	const notifyIdle = (): void => {
		if (idleNotified) return;
		idleNotified = true;
		callbacks.onIdleTimeout?.();
	};

	const closeRoom = (
		roomId: string,
		room: Room,
		hostCode: number,
		hostReason: string,
	): void => {
		rooms.delete(roomId);
		const closure = JSON.stringify({
			t: "room-closed",
		} satisfies RelayControlToGuest);
		for (const guest of room.guests.values()) {
			guest.send(closure);
			guest.close(4001, "room closed");
		}
		room.guests.clear();
		room.host.close(hostCode, hostReason);
	};
	const parseRegisteredLink = (link: string): { roomId: string } | null => {
		try {
			const outer = new URL(link);
			if (!allowedOrigins.has(outer.origin) || !outer.hash) return null;
			const inner = new URL(outer.hash.slice(1));
			const localRelay =
				inner.protocol === "ws:" &&
				isLoopbackBind(inner.hostname.replace(/^\[|\]$/g, "")) &&
				Number(inner.port) === server.port;
			if (!allowedRelayOrigins.has(inner.origin) && !localRelay) return null;
			const match = ROOM_LINK_PATH_RE.exec(inner.pathname);
			if (!match || Buffer.from(match[2]!, "base64url").byteLength !== 32)
				return null;
			return { roomId: match[1]! };
		} catch {
			return null;
		}
	};
	const registerRoom = async (req: Request): Promise<Response> => {
		const declaredLength = Number(req.headers.get("content-length") ?? "0");
		if (!Number.isFinite(declaredLength) || declaredLength > 8192)
			return new Response("payload too large", { status: 413 });
		const text = await req.text();
		if (text.length > 8192)
			return new Response("payload too large", { status: 413 });
		let payload: unknown;
		try {
			payload = JSON.parse(text);
		} catch {
			return new Response("invalid JSON", { status: 400 });
		}
		if (typeof payload !== "object" || payload === null)
			return new Response("invalid registration", { status: 400 });
		const record = payload as Record<string, unknown>;
		const link = typeof record.link === "string" ? record.link : "";
		const parsed = parseRegisteredLink(link);
		const room = parsed ? rooms.get(parsed.roomId) : undefined;
		if (!parsed || !room)
			return new Response("room not found", { status: 404 });
		const label =
			typeof record.label === "string" ? record.label.trim().slice(0, 120) : "";
		const cwd =
			typeof record.cwd === "string" ? record.cwd.trim().slice(0, 512) : "";
		room.registration = { link, label: label || roomTag(parsed.roomId), cwd };
		noteActivity(room);
		return new Response(null, { status: 204 });
	};
	const roomDirectory = (): Response => {
		const body = [...rooms.entries()]
			.filter(
				(entry): entry is [string, Room & { registration: RoomRegistration }] =>
					entry[1].registration !== undefined,
			)
			.map(([id, room]) => ({
				id,
				label: room.registration.label,
				cwd: room.registration.cwd,
				link: room.registration.link,
				guests: room.guests.size,
				startedAt: new Date(room.openedAtMs).toISOString(),
				lastActivityAt: new Date(room.lastActivityMs).toISOString(),
			}))
			.sort((a, b) => b.startedAt.localeCompare(a.startedAt));
		return Response.json(body, { headers: { "Cache-Control": "no-store" } });
	};

	const scheduleExpiry = (ws: RelaySocket): void => {
		const lifetimeSecs = ws.data.connectionLifetimeSecs;
		ws.data.expiryTimer = setTimeout(() => {
			log(
				`${ws.data.role} connection for room ${roomTag(ws.data.roomId)} reached its ${lifetimeSecs}s lifetime`,
			);
			ws.close(4001, "Cloudflare Access session expired");
		}, lifetimeSecs * 1000);
	};

	const server = Bun.serve<SocketData>({
		hostname: opts.bind,
		port: opts.port,
		fetch(req, srv): Response | undefined | Promise<Response> {
			const url = new URL(req.url);
			if (req.method === "GET" && url.pathname === "/healthz")
				return new Response("omp-collab-relay\n");

			const match =
				req.method === "GET" ? ROOM_PATH_RE.exec(url.pathname) : null;
			const role = url.searchParams.get("role");
			const origin = req.headers.get("origin");
			const forwarded =
				req.headers.has("cf-ray") ||
				req.headers.has("cf-connecting-ip") ||
				req.headers.has("x-forwarded-for");
			const localHostSocket =
				match !== null && role === "host" && origin === null && !forwarded;
			const localRegistration =
				req.method === "POST" &&
				url.pathname === "/api/rooms" &&
				origin === null &&
				!forwarded;
			const accessJwt = req.headers.get("cf-access-jwt-assertion");
			if (
				opts.requireAccessJwt &&
				!accessJwt &&
				!localHostSocket &&
				!localRegistration
			) {
				return new Response("unauthorized", {
					status: 401,
					headers: { "Cache-Control": "no-store" },
				});
			}
			if (localRegistration) return registerRoom(req);
			if (req.method === "GET" && url.pathname === "/api/rooms")
				return roomDirectory();

			const assetResponse = serveStatic(req, url.pathname, staticAssets);
			if (assetResponse) return assetResponse;
			if (!match || (role !== "host" && role !== "guest"))
				return new Response("not found", { status: 404 });
			if (origin !== null && !allowedOrigins.has(origin))
				return new Response("forbidden", { status: 403 });

			const connectionLifetimeSecs = Math.min(
				opts.maxConnectionSecs,
				accessTokenLifetimeSecs(accessJwt) ?? opts.maxConnectionSecs,
			);
			const data: SocketData = {
				roomId: match[1]!,
				role,
				peerId: 0,
				connectionLifetimeSecs,
			};
			if (srv.upgrade(req, { data })) return undefined;
			return new Response("websocket upgrade required", { status: 426 });
		},
		websocket: {
			maxPayloadLength: PROTOCOL_MAX_FRAME_BYTES,
			open(ws: RelaySocket): void {
				openSockets++;
				const { roomId, role } = ws.data;
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
					const now = noteActivity();
					rooms.set(roomId, {
						host: ws,
						guests: new Map(),
						nextPeerId: 1,
						openedAtMs: now,
						lastActivityMs: now,
					});
					scheduleExpiry(ws);
					log(
						`host connected, room ${roomTag(roomId)} open (rooms=${rooms.size}, sockets=${openSockets})`,
					);
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
				scheduleExpiry(ws);
				noteActivity(room);
				room.host.send(
					JSON.stringify({
						t: "peer-joined",
						peer: peerId,
					} satisfies RelayControlToHost),
				);
				log(
					`guest ${peerId} joined room ${roomTag(roomId)} (guests=${room.guests.size}, sockets=${openSockets})`,
				);
			},
			message(ws: RelaySocket, message: string | Buffer): void {
				if (
					typeof message === "string" ||
					message.byteLength < ENVELOPE_HEADER_LENGTH
				)
					return;
				const room = rooms.get(ws.data.roomId);
				if (!room) return;
				if (message.byteLength > opts.maxFrameBytes) {
					if (ws.data.role === "host" && room.host === ws) {
						log(
							`host frame of ${message.byteLength}B exceeds cap ${opts.maxFrameBytes}B, closing room ${roomTag(ws.data.roomId)}`,
						);
						closeRoom(ws.data.roomId, room, 4001, "frame too large");
					} else {
						log(
							`closing ${ws.data.role} socket: frame of ${message.byteLength}B exceeds cap ${opts.maxFrameBytes}B`,
						);
						ws.close(4013, "frame too large");
					}
					return;
				}
				if (ws.data.role === "host") {
					if (room.host !== ws) return;
					noteActivity(room);
					const peerId = message.readUInt32BE(0);
					if (peerId === 0) {
						for (const guest of room.guests.values()) guest.send(message);
					} else {
						room.guests.get(peerId)?.send(message);
					}
					return;
				}
				if (room.guests.get(ws.data.peerId) !== ws) return;
				noteActivity(room);
				message.writeUInt32BE(ws.data.peerId, 0);
				room.host.send(message);
			},
			close(ws: RelaySocket): void {
				clearTimeout(ws.data.expiryTimer);
				openSockets = Math.max(0, openSockets - 1);
				const { roomId, role, peerId } = ws.data;
				const room = rooms.get(roomId);
				if (!room) return;
				if (role === "host") {
					if (room.host !== ws) return;
					noteActivity();
					rooms.delete(roomId);
					const closure = JSON.stringify({
						t: "room-closed",
					} satisfies RelayControlToGuest);
					for (const guest of room.guests.values()) {
						guest.send(closure);
						guest.close(4001, "room closed");
					}
					room.guests.clear();
					log(
						`host left, room ${roomTag(roomId)} closed (rooms=${rooms.size}, sockets=${openSockets})`,
					);
					return;
				}
				if (room.guests.delete(peerId)) {
					noteActivity(room);
					room.host.send(
						JSON.stringify({
							t: "peer-left",
							peer: peerId,
						} satisfies RelayControlToHost),
					);
					log(
						`guest ${peerId} left room ${roomTag(roomId)} (guests=${room.guests.size}, sockets=${openSockets})`,
					);
				}
			},
		},
	});

	const sweepMs = Math.min(
		Math.max(Math.floor(opts.idleTimeoutSecs * 250), 250),
		30_000,
	);
	const sweeper = setInterval(() => {
		const now = Date.now();
		const cutoff = now - opts.idleTimeoutSecs * 1000;
		let closedIdleRoom = false;
		for (const [roomId, room] of rooms) {
			if (room.lastActivityMs > cutoff) continue;
			log(`room ${roomTag(roomId)} idle for ${opts.idleTimeoutSecs}s, closing`);
			closeRoom(roomId, room, 4001, "room closed");
			closedIdleRoom = true;
		}
		if (
			rooms.size === 0 &&
			(closedIdleRoom ||
				now - lastRelayActivityMs > opts.idleTimeoutSecs * 1000)
		)
			notifyIdle();
	}, sweepMs);

	const displayHost = opts.bind.includes(":") ? `[${opts.bind}]` : opts.bind;
	log(
		`listening on http://${displayHost}:${server.port} ` +
			`(guests/room<=${opts.maxGuestsPerRoom}, sockets<=${opts.maxSockets}, ` +
			`frame<=${opts.maxFrameBytes}B, idle=${opts.idleTimeoutSecs}s, connection<=${opts.maxConnectionSecs}s, ` +
			`access-jwt=${opts.requireAccessJwt ? "required" : "optional"})`,
	);

	return {
		url: `ws://${displayHost}:${server.port}`,
		port: server.port,
		stop(): void {
			if (stopped) return;
			stopped = true;
			clearInterval(sweeper);
			for (const [roomId, room] of rooms)
				closeRoom(roomId, room, 4001, "relay shutting down");
			server.stop(true);
		},
	};
}

function usage(): string {
	return `usage: omp-collab-relay [options]

Options:
  --port <n>                    Loopback port (default: ${DEFAULT_OPTIONS.port})
  --bind <address>              Loopback bind address (default: ${DEFAULT_OPTIONS.bind})
  --max-guests-per-room <n>     Guest cap per room (default: ${DEFAULT_OPTIONS.maxGuestsPerRoom})
  --max-sockets <n>             Total socket cap (default: ${DEFAULT_OPTIONS.maxSockets})
  --max-frame-bytes <n>         Frame cap, at most ${PROTOCOL_MAX_FRAME_BYTES}
  --idle-timeout-secs <n>       Shut down after room/relay inactivity (default: ${DEFAULT_OPTIONS.idleTimeoutSecs})
  --max-connection-secs <n>     Hard WebSocket lifetime (default: ${DEFAULT_OPTIONS.maxConnectionSecs})
  --allowed-origin <https-url>  Browser Origin to allow; repeatable (default: ${DEFAULT_OPTIONS.allowedOrigins.join(", ")})
  --require-access-jwt          Require a Cloudflare Access JWT except for the local native host
  --web-root <absolute-path>    Serve the browser guest client from this directory
  --quiet                       Suppress relay logs
  --help                        Show this help`;
}

function parseInteger(flag: string, raw: string | undefined): number {
	const value = Number(raw);
	if (!Number.isInteger(value)) throw new Error(`${flag} requires an integer`);
	return value;
}

function parseArgs(argv: readonly string[]): Partial<RelayOptions> {
	const parsed: Partial<RelayOptions> = {};
	const origins: string[] = [];
	for (let i = 0; i < argv.length; i++) {
		const flag = argv[i]!;
		const next = (): string => {
			const value = argv[++i];
			if (value === undefined) throw new Error(`${flag} requires a value`);
			return value;
		};
		switch (flag) {
			case "--port":
				parsed.port = parseInteger(flag, next());
				break;
			case "--bind":
				parsed.bind = next();
				break;
			case "--max-guests-per-room":
				parsed.maxGuestsPerRoom = parseInteger(flag, next());
				break;
			case "--max-sockets":
				parsed.maxSockets = parseInteger(flag, next());
				break;
			case "--max-frame-bytes":
				parsed.maxFrameBytes = parseInteger(flag, next());
				break;
			case "--idle-timeout-secs":
				parsed.idleTimeoutSecs = parseInteger(flag, next());
				break;
			case "--max-connection-secs":
				parsed.maxConnectionSecs = parseInteger(flag, next());
				break;
			case "--allowed-origin":
				origins.push(next());
				break;
			case "--web-root":
				parsed.webRoot = next();
				break;
			case "--require-access-jwt":
				parsed.requireAccessJwt = true;
				break;
			case "--quiet":
				parsed.quiet = true;
				break;
			case "--help":
				console.log(usage());
				process.exit(0);
			default:
				throw new Error(`unknown option: ${flag}`);
		}
	}
	if (origins.length > 0) parsed.allowedOrigins = origins;
	return parsed;
}

if (import.meta.main) {
	let relay: CollabRelay | undefined;
	let stopping = false;
	const shutdown = (code: number): void => {
		if (stopping) return;
		stopping = true;
		relay?.stop();
		process.exit(code);
	};
	try {
		const options = parseArgs(Bun.argv.slice(2));
		relay = startRelay(options, {
			onIdleTimeout: () => {
				console.error(
					`[omp-collab-relay] idle for ${options.idleTimeoutSecs ?? DEFAULT_OPTIONS.idleTimeoutSecs}s; shutting down`,
				);
				shutdown(0);
			},
		});
	} catch (error) {
		console.error(
			`omp-collab-relay: ${error instanceof Error ? error.message : String(error)}`,
		);
		console.error(usage());
		process.exit(2);
	}
	process.on("SIGINT", () => shutdown(0));
	process.on("SIGTERM", () => shutdown(0));
}
