/**
 * Contract tests mirror OMP v17.2.1's local relay. Hardening tests defend the
 * additional public-exposure boundaries in this package.
 *
 * Run with: bun test packages/omp-collab-relay/relay.test.ts
 */
import { join } from "node:path";
import { COLLAB_PROTO, ENVELOPE_HEADER_LENGTH, ROOM_ID_BYTES } from "@oh-my-pi/pi-wire";
import { afterEach, describe, expect, it } from "bun:test";
import { type CollabRelay, ROOM_PATH_RE, startRelay } from "./relay";

const ROOM = "RelayRoom_12345";
const OTHER_ROOM = "OtherRoom_67890";
const REQUEST_TIMEOUT_MS = 1_000;
const WEB_ROOT = join(import.meta.dir, "web");
// Integration exception: these tests exercise Bun's real WebSocket server and
// interval-driven idle sweeper. Timeout timers are hang guards; the two sleeps
// below deliberately cross a real sweep boundary that fake timers cannot drive
// without starving socket I/O.

let relay: CollabRelay | null = null;
const sockets: WebSocket[] = [];

function packEnvelope(peerId: number, payload: Uint8Array): Uint8Array {
	const out = new Uint8Array(4 + payload.byteLength);
	new DataView(out.buffer).setUint32(0, peerId, false);
	out.set(payload, 4);
	return out;
}

function unpackEnvelope(data: Uint8Array): { peerId: number; payload: Uint8Array } | null {
	if (data.byteLength < 4) return null;
	const peerId = new DataView(data.buffer, data.byteOffset, 4).getUint32(0, false);
	return { peerId, payload: data.subarray(4) };
}

function relayHttpUrl(): string {
	if (!relay) throw new Error("relay not started");
	return relay.url.replace(/^ws:/, "http:");
}

interface Inbox {
	queue: MessageEvent[];
	waiters: Array<(event: MessageEvent) => void>;
}

const inboxes = new Map<WebSocket, Inbox>();

function socket(path: string, headers?: Record<string, string>): WebSocket {
	if (!relay) throw new Error("relay not started");
	const ws = new WebSocket(`${relay.url}${path}`, headers ? { headers } : undefined);
	ws.binaryType = "arraybuffer";
	const inbox: Inbox = { queue: [], waiters: [] };
	inboxes.set(ws, inbox);
	ws.addEventListener("message", event => {
		const waiter = inbox.waiters.shift();
		if (waiter) waiter(event as MessageEvent);
		else inbox.queue.push(event as MessageEvent);
	});
	sockets.push(ws);
	return ws;
}

function nextMessage(ws: WebSocket, label: string, timeoutMs = REQUEST_TIMEOUT_MS): Promise<MessageEvent> {
	const inbox = inboxes.get(ws);
	if (!inbox) throw new Error("socket not created via socket()");
	const queued = inbox.queue.shift();
	if (queued) return Promise.resolve(queued);
	const { promise, resolve, reject } = Promise.withResolvers<MessageEvent>();
	const timer = setTimeout(() => {
		const index = inbox.waiters.indexOf(onEvent);
		if (index !== -1) inbox.waiters.splice(index, 1);
		reject(new Error(`timed out waiting for ${label}`));
	}, timeoutMs);
	const onEvent = (event: MessageEvent): void => {
		clearTimeout(timer);
		resolve(event);
	};
	inbox.waiters.push(onEvent);
	return promise;
}

function waitEvent<T extends Event>(
	ws: WebSocket,
	type: string,
	label: string,
	timeoutMs = REQUEST_TIMEOUT_MS,
): Promise<T> {
	const { promise, resolve, reject } = Promise.withResolvers<T>();
	let timer: Timer | undefined;
	const cleanup = (): void => {
		ws.removeEventListener(type, onEvent);
		clearTimeout(timer);
	};
	const onEvent = (event: Event): void => {
		cleanup();
		resolve(event as T);
	};
	timer = setTimeout(() => {
		cleanup();
		reject(new Error(`timed out waiting for ${label}`));
	}, timeoutMs);
	ws.addEventListener(type, onEvent);
	return promise;
}

async function waitFor<T>(promise: Promise<T>, label: string, timeoutMs = 5_000): Promise<T> {
	return await Promise.race([
		promise,
		Bun.sleep(timeoutMs).then(() => {
			throw new Error(`timed out waiting for ${label}`);
		}),
	]);
}

function waitOpen(ws: WebSocket): Promise<Event> {
	if (ws.readyState === WebSocket.OPEN) return Promise.resolve(new Event("open"));
	return waitEvent(ws, "open", "socket open");
}

async function waitText(ws: WebSocket, label: string, timeoutMs = REQUEST_TIMEOUT_MS): Promise<string> {
	const event = await nextMessage(ws, label, timeoutMs);
	if (typeof event.data !== "string") throw new Error(`${label} was not TEXT`);
	return event.data;
}

async function waitBinary(ws: WebSocket, label: string): Promise<Uint8Array> {
	const event = await nextMessage(ws, label);
	const data: unknown = event.data;
	if (data instanceof ArrayBuffer) return new Uint8Array(data);
	if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
	throw new Error(`${label} was not binary`);
}

function closeSocket(ws: WebSocket): void {
	if (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN) ws.close(1000);
}

function start(
	overrides: Parameters<typeof startRelay>[0] = {},
	callbacks: Parameters<typeof startRelay>[1] = {},
): CollabRelay {
	relay = startRelay({ port: 0, quiet: true, ...overrides }, callbacks);
	return relay;
}

afterEach(() => {
	for (const ws of sockets.splice(0)) closeSocket(ws);
	inboxes.clear();
	relay?.stop();
	relay = null;
});

describe("omp-collab-relay contract", () => {
	it("serves health and validates relay requests", async () => {
		start();

		const health = await fetch(`${relayHttpUrl()}/healthz`);
		expect(health.status).toBe(200);
		expect(await health.text()).toBe("omp-collab-relay\n");

		expect((await fetch(`${relayHttpUrl()}/nope`)).status).toBe(404);
		expect((await fetch(`${relayHttpUrl()}/r/${ROOM}?role=admin`)).status).toBe(404);

		const absentOrigin = await fetch(`${relayHttpUrl()}/r/${ROOM}?role=host`);
		expect(absentOrigin.status).toBe(426);

		const allowedOrigin = await fetch(`${relayHttpUrl()}/r/${ROOM}?role=host`, {
			headers: { Origin: "https://omp.midsorbet.me" },
		});
		expect(allowedOrigin.status).toBe(426);

		const wrongOrigin = await fetch(`${relayHttpUrl()}/r/${ROOM}?role=host`, {
			headers: { Origin: "https://evil.example" },
		});
		expect(wrongOrigin.status).toBe(403);
	});

	it("requires Cloudflare Access for web and guest traffic while admitting the local native host", async () => {
		start({ webRoot: WEB_ROOT, requireAccessJwt: true });

		expect((await fetch(`${relayHttpUrl()}/healthz`)).status).toBe(200);
		expect((await fetch(`${relayHttpUrl()}/`)).status).toBe(401);
		expect((await fetch(`${relayHttpUrl()}/r/${ROOM}?role=guest`)).status).toBe(401);
		expect((await fetch(`${relayHttpUrl()}/r/${ROOM}?role=host`)).status).toBe(426);
		const forwardedHost = await fetch(`${relayHttpUrl()}/r/${ROOM}?role=host`, {
			headers: { "Cf-Ray": "test" },
		});
		expect(forwardedHost.status).toBe(401);

		const accessHeaders = {
			"Cf-Access-Jwt-Assertion": "header.payload.signature",
			Origin: "https://omp.midsorbet.me",
		};
		expect((await fetch(`${relayHttpUrl()}/`, { headers: accessHeaders })).status).toBe(200);
		expect((await fetch(`${relayHttpUrl()}/r/${ROOM}?role=guest`, { headers: accessHeaders })).status).toBe(426);
	});

	it("serves the same-origin browser client with hardened headers", async () => {
		start({ webRoot: WEB_ROOT });

		const index = await fetch(`${relayHttpUrl()}/`);
		expect(index.status).toBe(200);
		expect(index.headers.get("cache-control")).toBe("no-store");
		expect(index.headers.get("content-type")).toMatch(/^text\/html/);
		expect(index.headers.get("cross-origin-resource-policy")).toBe("same-origin");
		const csp = index.headers.get("content-security-policy");
		expect(csp).toContain("connect-src 'self'");
		expect(csp).toContain("script-src 'self'");
		expect(csp).not.toContain("wss:");
		expect(csp).not.toContain("script-src 'self' 'unsafe-inline'");

		const html = await index.text();
		expect(html).toContain('<div id="root"></div>');
		expect(html).not.toContain("um.can.ac");
		expect(html).not.toMatch(/<script(?![^>]*\bsrc=)/);
		const scriptName = /src="\.\/([^"]+\.js)"/.exec(html)?.[1];
		expect(scriptName).toBeTruthy();

		const script = await fetch(`${relayHttpUrl()}/${scriptName}`);
		expect(script.status).toBe(200);
		expect(script.headers.get("cache-control")).toContain("immutable");
		expect(script.headers.get("content-type")).toMatch(/^text\/javascript/);

		const head = await fetch(`${relayHttpUrl()}/`, { method: "HEAD" });
		expect(head.status).toBe(200);
		expect(await head.text()).toBe("");
		expect((await fetch(`${relayHttpUrl()}/`, { method: "POST" })).status).toBe(404);
		expect((await fetch(`${relayHttpUrl()}/package.json`)).status).toBe(404);
	});

	it("rewrites loopback browser links to the authenticated same origin", async () => {
		const key = "k".repeat(43);
		const script = await Bun.file(join(WEB_ROOT, "relay-url.js")).text();
		const replacements: string[] = [];
		const window = {
			location: {
				hash: `#ws://127.0.0.1:17475/r/${ROOM}.${key}`,
				hostname: "omp.midsorbet.me",
				port: "",
				pathname: "/",
				protocol: "https:",
				search: "",
			},
		};
		const history = {
			replaceState: (_state: unknown, _unused: string, url: string) => replacements.push(url),
		};

		new Function("window", "history", "URL", script)(window, history, URL);

		expect(replacements).toEqual([`/#wss://omp.midsorbet.me/r/${ROOM}.${key}`]);
	});

	it("accepts OMP clients without an Origin header", async () => {
		start();
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		expect(host.readyState).toBe(WebSocket.OPEN);
	});

	it("rejects guests before a host creates the room", async () => {
		start();
		const guest = socket(`/r/${ROOM}?role=guest`);
		const close = await waitEvent<CloseEvent>(guest, "close", "missing-room guest close");
		expect(close.code).toBe(4004);
		expect(close.reason).toBe("no such room");
	});

	it("routes opaque envelopes between host and guest", async () => {
		start();
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		expect(JSON.parse(await waitText(host, "peer join"))).toEqual({ t: "peer-joined", peer: 1 });

		guest.send(packEnvelope(0, new Uint8Array([1, 2, 3])));
		const fromGuest = unpackEnvelope(await waitBinary(host, "guest envelope"));
		expect(fromGuest?.peerId).toBe(1);
		expect(fromGuest?.payload).toEqual(new Uint8Array([1, 2, 3]));

		const broadcast = waitBinary(guest, "broadcast to guest");
		host.send(packEnvelope(0, new Uint8Array([9])));
		expect(unpackEnvelope(await broadcast)?.payload).toEqual(new Uint8Array([9]));

		const targeted = waitBinary(guest, "targeted guest frame");
		host.send(packEnvelope(1, new Uint8Array([7])));
		expect(unpackEnvelope(await targeted)?.payload).toEqual(new Uint8Array([7]));
	});

	it("enforces one host and closes guests when the room host leaves", async () => {
		start();
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const duplicateHost = socket(`/r/${ROOM}?role=host`);
		const duplicateClose = await waitEvent<CloseEvent>(duplicateHost, "close", "duplicate host close");
		expect(duplicateClose.code).toBe(4009);
		expect(duplicateClose.reason).toBe("a host is already connected for this room");

		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		expect(JSON.parse(await waitText(host, "peer join"))).toEqual({ t: "peer-joined", peer: 1 });
		const closure = waitText(guest, "room close control");
		const guestClose = waitEvent<CloseEvent>(guest, "close", "guest room close");
		host.close(1000);
		expect(JSON.parse(await closure)).toEqual({ t: "room-closed" });
		expect((await guestClose).code).toBe(4001);
	});
});

describe("omp-collab-relay hardening", () => {
	it("refuses non-loopback bind addresses and invalid caps", () => {
		expect(() => startRelay({ port: 0, quiet: true, bind: "0.0.0.0" })).toThrow(/non-loopback/);
		expect(() => startRelay({ port: 0, quiet: true, bind: "192.168.4.207" })).toThrow(/non-loopback/);
		expect(() => startRelay({ port: 0, quiet: true, maxFrameBytes: 16 * 1024 * 1024 + 1 })).toThrow(
			/cannot exceed/,
		);
		expect(() => startRelay({ port: 0, quiet: true, webRoot: "relative" })).toThrow(/existing absolute directory/);
	});

	it("caps an authenticated guest connection at the Access JWT expiry", async () => {
		start({ requireAccessJwt: true, maxConnectionSecs: 10 });
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);

		const exp = Math.floor(Date.now() / 1000) + 1;
		const token = `header.${Buffer.from(JSON.stringify({ exp })).toString("base64url")}.signature`;
		const guest = socket(`/r/${ROOM}?role=guest`, {
			"Cf-Access-Jwt-Assertion": token,
			Origin: "https://omp.midsorbet.me",
		});
		await waitOpen(guest);
		const close = await waitEvent<CloseEvent>(guest, "close", "Access JWT expiry close", 3_000);
		expect(close.code).toBe(4001);
		expect(close.reason).toBe("Cloudflare Access session expired");
	});

	it("caps guests per room with retryable 4030", async () => {
		start();
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		expect(JSON.parse(await waitText(host, "peer join"))).toEqual({ t: "peer-joined", peer: 1 });

		const extraGuest = socket(`/r/${ROOM}?role=guest`);
		const close = await waitEvent<CloseEvent>(extraGuest, "close", "extra guest close");
		expect(close.code).toBe(4030);
		expect(close.reason).toBe("room is full, try again later");

		guest.send(packEnvelope(0, new Uint8Array([42])));
		expect(unpackEnvelope(await waitBinary(host, "post-reject envelope"))?.payload).toEqual(new Uint8Array([42]));
	});

	it("caps concurrent rooms with fatal 4029", async () => {
		start();
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const secondHost = socket(`/r/${OTHER_ROOM}?role=host`);
		const close = await waitEvent<CloseEvent>(secondHost, "close", "second room close");
		expect(close.code).toBe(4029);
		expect(close.reason).toBe("room is full");
	});

	it("caps total sockets with fatal 4029", async () => {
		start({ maxSockets: 2, maxGuestsPerRoom: 4 });
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		const overflow = socket(`/r/${ROOM}?role=guest`);
		const close = await waitEvent<CloseEvent>(overflow, "close", "overflow socket close");
		expect(close.code).toBe(4029);
		expect(close.reason).toBe("relay is at its socket limit");
	});

	it("closes a guest exceeding the frame cap with retryable 4013", async () => {
		start({ maxFrameBytes: 1024, maxGuestsPerRoom: 2 });
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		await waitText(host, "peer join");

		const guestClose = waitEvent<CloseEvent>(guest, "close", "oversized frame close", 3_000);
		guest.send(packEnvelope(0, new Uint8Array(4096)));
		const close = await guestClose;
		expect(close.code).toBe(4013);
		expect(close.reason).toBe("frame too large");
		expect(JSON.parse(await waitText(host, "peer left"))).toEqual({ t: "peer-left", peer: 1 });
	});

	it("tears the room down coherently when the host exceeds the frame cap", async () => {
		start({ maxFrameBytes: 1024 });
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		await waitText(host, "peer join");

		const closure = waitText(guest, "room close control", 3_000);
		const guestClose = waitEvent<CloseEvent>(guest, "close", "guest close", 3_000);
		const hostClose = waitEvent<CloseEvent>(host, "close", "host close", 3_000);
		host.send(packEnvelope(0, new Uint8Array(4096)));
		expect(JSON.parse(await closure)).toEqual({ t: "room-closed" });
		expect((await guestClose).code).toBe(4001);
		expect((await hostClose).code).toBe(4001);
	});

	it("resets the room idle deadline on valid frame activity", async () => {
		start({ idleTimeoutSecs: 1 });
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		await waitText(host, "peer join");

		await Bun.sleep(700);
		guest.send(packEnvelope(0, new Uint8Array([1])));
		await waitBinary(host, "activity frame");
		await Bun.sleep(700);
		expect(host.readyState).toBe(WebSocket.OPEN);

		const hostClose = waitEvent<CloseEvent>(host, "close", "post-activity idle close", 3_000);
		expect((await hostClose).code).toBe(4001);
	});

	it("tears down idle rooms and reports relay idle", async () => {
		const idle = Promise.withResolvers<void>();
		start({ idleTimeoutSecs: 1 }, { onIdleTimeout: idle.resolve });
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		await waitText(host, "peer join");

		const closure = waitText(guest, "idle room close control", 5_000);
		const guestClose = waitEvent<CloseEvent>(guest, "close", "idle guest close", 5_000);
		const hostClose = waitEvent<CloseEvent>(host, "close", "idle host close", 5_000);
		expect(JSON.parse(await closure)).toEqual({ t: "room-closed" });
		expect((await guestClose).code).toBe(4001);
		expect((await hostClose).code).toBe(4001);
		await waitFor(idle.promise, "relay idle callback");
	});

	it("reports relay idle even if no room opens", async () => {
		const idle = Promise.withResolvers<void>();
		start({ idleTimeoutSecs: 1 }, { onIdleTimeout: idle.resolve });
		await waitFor(idle.promise, "empty relay idle callback");
	});

	it("stops hosts with a fatal close so OMP does not reconnect", async () => {
		const running = start();
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const hostClose = waitEvent<CloseEvent>(host, "close", "relay stop close");
		running.stop();
		relay = null;
		expect((await hostClose).code).toBe(4001);
	});
});

describe("upstream wire conformance", () => {
	it("matches OMP 17.2.1 relay assumptions", () => {
		expect(ENVELOPE_HEADER_LENGTH).toBe(4);
		const roomIdLength = Math.ceil((ROOM_ID_BYTES * 8) / 6);
		expect(ROOM_PATH_RE.test(`/r/${"A".repeat(roomIdLength)}`)).toBe(true);
		expect(COLLAB_PROTO).toBe(3);
	});
});
