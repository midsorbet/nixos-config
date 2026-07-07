/**
 * Focused tests for the hardened OMP collab relay.
 *
 * Contract cases mirror the upstream reference tests
 * (oh-my-pi packages/collab-web/test/local-relay.test.ts, v16.3.2);
 * hardening cases cover the caps this relay adds on top.
 *
 * Run with: bun test packages/omp-collab-tunnel/relay.test.ts
 */
import { COLLAB_PROTO, ENVELOPE_HEADER_LENGTH, ROOM_ID_BYTES } from "@oh-my-pi/pi-wire";
import { afterEach, describe, expect, it } from "bun:test";
import { type CollabRelay, ROOM_PATH_RE, startRelay } from "./relay";

const ROOM = "RelayRoom_12345";
const OTHER_ROOM = "OtherRoom_67890";
const REQUEST_TIMEOUT_MS = 1_000;

let relay: CollabRelay | null = null;
const sockets: WebSocket[] = [];

/** 4-byte big-endian peerId prefix + sealed payload (matches OMP's packEnvelope). */
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

function socket(path: string): WebSocket {
	if (!relay) throw new Error("relay not started");
	const ws = new WebSocket(`${relay.url}${path}`);
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
		const idx = inbox.waiters.indexOf(onEvent);
		if (idx !== -1) inbox.waiters.splice(idx, 1);
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

function start(overrides: Parameters<typeof startRelay>[0] = {}, callbacks: Parameters<typeof startRelay>[1] = {}): CollabRelay {
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
	it("serves /healthz and rejects non-relay requests", async () => {
		start();

		const health = await fetch(`${relayHttpUrl()}/healthz`);
		expect(health.status).toBe(200);
		expect(await health.text()).toBe("ok\n");

		const notFound = await fetch(`${relayHttpUrl()}/nope`);
		expect(notFound.status).toBe(404);

		const badRole = await fetch(`${relayHttpUrl()}/r/${ROOM}?role=admin`);
		expect(badRole.status).toBe(404);

		const upgradeRequired = await fetch(`${relayHttpUrl()}/r/${ROOM}?role=host`);
		expect(upgradeRequired.status).toBe(426);
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
	it("refuses non-loopback bind addresses", () => {
		expect(() => startRelay({ port: 0, quiet: true, bind: "0.0.0.0" })).toThrow(/non-loopback/);
		expect(() => startRelay({ port: 0, quiet: true, bind: "192.168.4.207" })).toThrow(/non-loopback/);
	});

	it("caps guests per room with non-fatal 4030 so a reconnecting guest recovers", async () => {
		start(); // maxGuestsPerRoom defaults to 1
		const host = socket(`/r/${ROOM}?role=host`);
		await waitOpen(host);
		const guest = socket(`/r/${ROOM}?role=guest`);
		await waitOpen(guest);
		expect(JSON.parse(await waitText(host, "peer join"))).toEqual({ t: "peer-joined", peer: 1 });

		const extraGuest = socket(`/r/${ROOM}?role=guest`);
		const close = await waitEvent<CloseEvent>(extraGuest, "close", "extra guest close");
		// Non-fatal by design: a legitimate guest racing its own not-yet-reaped
		// stale socket must be able to retry (fatal 4029 would kick it forever).
		// App-range 4030 because Cloudflare rewrites reserved 1013 to 1006.
		expect(close.code).toBe(4030);
		expect(close.reason).toBe("room is full, try again later");

		// The room keeps working for the accepted pair.
		guest.send(packEnvelope(0, new Uint8Array([42])));
		expect(unpackEnvelope(await waitBinary(host, "post-reject envelope"))?.payload).toEqual(new Uint8Array([42]));
	});

	it("caps concurrent rooms with fatal 4029", async () => {
		start(); // maxRooms defaults to 1
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

	it("closes a guest exceeding the frame cap with non-fatal 4013", async () => {
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

		// Host is informed and keeps running.
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

		// No silent split-brain: guests get room-closed + fatal 4001, and the
		// host is fatally closed too instead of reconnecting into an empty room.
		expect(JSON.parse(await closure)).toEqual({ t: "room-closed" });
		expect((await guestClose).code).toBe(4001);
		expect((await hostClose).code).toBe(4001);
	});

	// Real-clock integration test: the idle sweeper runs on a real interval
	// inside startRelay while WebSocket events flow through real socket I/O;
	// fake timers cannot advance the sweep without starving the event pump.
	it("tears down idle rooms with fatal 4001 and reports relay idle", async () => {
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

		// The slot is free again: a new host can recreate the room if the
		// embedding process chooses not to exit from the idle callback.
		const nextHost = socket(`/r/${ROOM}?role=host`);
		await waitOpen(nextHost);
	});

	it("reports relay idle even if no room ever opens", async () => {
		const idle = Promise.withResolvers<void>();
		start({ idleTimeoutSecs: 1 }, { onIdleTimeout: idle.resolve });

		await waitFor(idle.promise, "empty relay idle callback");
	});
});

// Drift tripwire: @oh-my-pi/pi-wire is version-locked to the managed OMP
// release. If a bump changes any of these, the relay contract must be
// re-verified against the new OMP source before the pin advances.
describe("upstream wire conformance", () => {
	it("matches the relay's wire assumptions", () => {
		// Envelope prefix: [4B uint32 BE peerId][sealed payload].
		expect(ENVELOPE_HEADER_LENGTH).toBe(4);

		// Room ids are base64url(ROOM_ID_BYTES) and must pass the room path.
		const roomIdLength = Math.ceil((ROOM_ID_BYTES * 8) / 6);
		const sampleRoomId = "A".repeat(roomIdLength);
		expect(ROOM_PATH_RE.test(`/r/${sampleRoomId}`)).toBe(true);

		// The relay is content-blind, but this workflow targets collab wire
		// protocol v3 (host rejects mismatched guests at hello).
		expect(COLLAB_PROTO).toBe(3);
	});
});
