import { afterEach, describe, expect, it } from "bun:test";
import {
	type CollabRelay,
	type HerdrDashboard,
	type HerdrPane,
	type HerdrSubscription,
	type HerdrTransport,
	createHerdrDashboard,
	forwardFrame,
	pumpOutbox,
	SOCKET_SEND_HIGH_WATER_BYTES,
	startRelay,
} from "./relay";

const SESSION = {
	source: "herdr:omp",
	agent: "omp",
	kind: "path" as const,
	value: "/tmp/omp-session.json",
};
const PANE: HerdrPane = {
	id: "w1:p1",
	identity: "herdr:omp:omp:path:/tmp/omp-session.json",
	session: SESSION,
	label: "OMP",
	cwd: "/Users/me/vault",
	status: "idle",
	focused: true,
};

class FakeHerdrTransport implements HerdrTransport {
	requests: Array<{ method: string; params: Record<string, unknown> }> = [];
	snapshotAgents: unknown[] = [PANE_TO_WIRE(PANE)];
	event: ((value: unknown) => void) | undefined;
	closed = false;
	prompted = 0;
	async request(request: {
		id: string;
		method: string;
		params: Record<string, unknown>;
	}): Promise<unknown> {
		this.requests.push(request);
		if (request.method === "session.snapshot") {
			return {
				id: request.id,
				result: {
					type: "session_snapshot",
					snapshot: {
						version: "0.8.0",
						protocol: 19,
						workspaces: [],
						tabs: [],
						panes: this.snapshotAgents,
						layouts: [],
						agents: this.snapshotAgents,
					},
				},
			};
		}
		if (request.method === "agent.prompt") {
			this.prompted++;
			return {
				id: request.id,
				result: { type: "agent_prompted", agent: PANE_TO_WIRE(PANE) },
			};
		}
		if (request.method === "plugin.pane.open") {
			return {
				id: request.id,
				result: {
					type: "plugin_pane_opened",
					plugin_pane: {
						plugin_id: "local.omp-dashboard",
						entrypoint: "agent",
						pane: PANE_TO_WIRE(PANE),
					},
				},
			};
		}
		throw new Error(`unexpected method ${request.method}`);
	}
	async subscribe(
		request: { id: string; method: string; params: Record<string, unknown> },
		onEvent: (value: unknown) => void,
		onClose: (error?: Error) => void,
	): Promise<HerdrSubscription> {
		this.requests.push(request);
		expect(request.method).toBe("events.subscribe");
		expect(request.params).toEqual({
			subscriptions: expect.arrayContaining([
				{ type: "pane.created" },
				{ type: "pane.updated" },
				{ type: "pane.closed" },
			]),
		});
		this.event = onEvent;
		return {
			close: () => {
				this.closed = true;
				onClose();
			},
		};
	}
}

function PANE_TO_WIRE(pane: HerdrPane): Record<string, unknown> {
	return {
		pane_id: pane.id,
		agent: "omp",
		agent_session: pane.session,
		name: pane.label,
		foreground_cwd: pane.cwd,
		agent_status: pane.status,
		focused: pane.focused,
	};
}

function handoffLink(relay: CollabRelay, room: string): string {
	const secret = Buffer.alloc(48, 7).toString("base64url");
	return `https://omp.midsorbet.me/#${relay.url}/r/${room}.${secret}`;
}

function hardWrapTuiText(text: string, width = 38): string {
	const contentWidth = width - 1;
	const lines: string[] = [];
	for (let offset = 0; offset < text.length; offset += contentWidth)
		lines.push(` ${text.slice(offset, offset + contentWidth)}`);
	return lines.join("\n");
}

let relay: CollabRelay | undefined;

afterEach(() => {
	relay?.stop();
	relay = undefined;
});
describe("local service control", () => {
	it("acknowledges stop before soft shutdown", async () => {
		const stopped = Promise.withResolvers<void>();
		relay = startRelay(
			{ port: 0, quiet: true },
			{
				onSoftShutdown: () => {
					relay?.stop();
					stopped.resolve();
				},
			},
		);

		const response = await fetch(
			`${relay.url.replace(/^ws:/, "http:")}/api/service/stop`,
			{ method: "POST" },
		);
		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({ status: "stopping" });
		await stopped.promise;
		relay = undefined;
	});
});

describe("Herdr socket dashboard", () => {
	it("bootstraps from session.snapshot and applies native lifecycle events", async () => {
		const transport = new FakeHerdrTransport();
		const dashboard = createHerdrDashboard({
			socketPath: "/tmp/herdr.sock",
			vaultRoot: "/Users/me/vault",
			activationTimeoutMs: 100,
			reconnectDelayMs: 1,
			pluginId: "local.omp-dashboard",
			pluginEntrypoint: "agent",
			transport,
			sleep: async () => {},
		});
		expect(await dashboard.listPanes()).toEqual([PANE]);
		transport.event?.({
			event: "PaneUpdated",
			data: {
				type: "pane_updated",
				pane: { ...PANE_TO_WIRE(PANE), agent_status: "working" },
			},
		});
		expect((await dashboard.listPanes())[0]?.status).toBe("working");
		dashboard.stop();
	});

	it("uses plugin.pane.open and agent.prompt wire methods", async () => {
		const transport = new FakeHerdrTransport();
		const dashboard = createHerdrDashboard({
			socketPath: "/tmp/herdr.sock",
			vaultRoot: "/Users/me/vault",
			activationTimeoutMs: 100,
			reconnectDelayMs: 1,
			pluginId: "local.omp-dashboard",
			pluginEntrypoint: "agent",
			transport,
			sleep: async () => {},
		});
		await dashboard.listPanes();
		expect(await dashboard.createAgent()).toEqual(PANE);
		await dashboard.promptAgent(PANE.id);
		expect(transport.requests.map((request) => request.method)).toEqual([
			"session.snapshot",
			"events.subscribe",
			"session.snapshot",
			"plugin.pane.open",
			"agent.prompt",
		]);
		expect(transport.requests.at(-1)?.params).toEqual({
			target: PANE.id,
			text: "/collab",
		});
		dashboard.stop();
	});
});

describe("Herdr-driven collab activation", () => {
	it("captures a hard-wrapped live link and deduplicates concurrent prompts", async () => {
		let prompts = 0;
		let renderedLink = "";
		const prompted = Promise.withResolvers<void>();
		const dashboard: HerdrDashboard = {
			listPanes: async () => [PANE],
			createAgent: async () => PANE,
			promptAgent: async () => {
				prompts++;
				prompted.resolve();
			},
			readPane: async () => ({
				text: renderedLink,
				revision: renderedLink ? 2 : 1,
			}),
			refresh: async () => {},
			stop: () => {},
		};
		relay = startRelay({ port: 0, quiet: true }, { herdrDashboard: dashboard });
		const room = "RelayRoom_12345";
		const host = new WebSocket(`${relay.url}/r/${room}?role=host`);
		await new Promise<void>((resolve, reject) => {
			host.addEventListener("open", () => resolve(), { once: true });
			host.addEventListener("error", () => reject(new Error("host failed")), {
				once: true,
			});
		});
		const headers = { Origin: "https://omp.midsorbet.me" };
		const first = fetch(
			`${relay.url.replace(/^ws:/, "http:")}/api/agents/w1%3Ap1/activate`,
			{ method: "POST", headers },
		);
		const second = fetch(
			`${relay.url.replace(/^ws:/, "http:")}/api/agents/w1%3Ap1/activate`,
			{ method: "POST", headers },
		);
		await prompted.promise;
		renderedLink = [
			" Collab session started!",
			hardWrapTuiText(handoffLink(relay, room).replace(/^https:\/\//, "")),
			" Anyone with this link can watch the session.",
		].join("\n");
		expect(await (await first).json()).toEqual({
			link: `https://omp.midsorbet.me/#wss://omp.midsorbet.me/r/${room}.${Buffer.alloc(48, 7).toString("base64url")}`,
		});
		expect(await (await second).json()).toEqual({
			link: `https://omp.midsorbet.me/#wss://omp.midsorbet.me/r/${room}.${Buffer.alloc(48, 7).toString("base64url")}`,
		});
		expect(prompts).toBe(1);
		host.close();
	});
});

function fakeGuestSocket() {
	const sent: Buffer[] = [];
	const state = { buffered: 0 };
	const fake = {
		data: { outbox: [] as Buffer[] },
		getBufferedAmount: () => state.buffered,
		send(message: Buffer): number {
			state.buffered += message.byteLength;
			sent.push(Buffer.from(message));
			return message.byteLength;
		},
	};
	const socket = fake as unknown as Parameters<typeof forwardFrame>[0];
	return {
		socket,
		outbox: fake.data.outbox,
		sent,
		drain(bytes: number): void {
			state.buffered = Math.max(0, state.buffered - bytes);
			pumpOutbox(socket);
		},
	};
}

describe("backpressure-aware forwarding", () => {
	const FRAME = 1024 * 1024;

	it("queues frames past the high-water mark instead of dropping them", () => {
		const guest = fakeGuestSocket();
		const frames = Array.from({ length: 20 }, (_, i) =>
			Buffer.alloc(FRAME, i % 251),
		);
		for (const frame of frames) forwardFrame(guest.socket, frame);
		// Backpressure must engage well before the whole burst is accepted, and
		// every frame is still accounted for — none silently dropped.
		expect(guest.outbox.length).toBeGreaterThan(0);
		expect(guest.sent.length + guest.outbox.length).toBe(frames.length);
		// Draining the socket flushes the remainder from drain()/pumpOutbox.
		let guard = 0;
		while (guest.outbox.length > 0 && guard++ < frames.length + 5)
			guest.drain(SOCKET_SEND_HIGH_WATER_BYTES);
		expect(guest.outbox.length).toBe(0);
		expect(guest.sent.length).toBe(frames.length);
		for (let i = 0; i < frames.length; i++)
			expect(guest.sent[i]!.equals(frames[i]!)).toBe(true);
	});

	it("copies queued frames so handler-buffer reuse cannot corrupt them", () => {
		const guest = fakeGuestSocket();
		for (let i = 0; i < 9; i++)
			forwardFrame(guest.socket, Buffer.alloc(FRAME, 1));
		expect(guest.outbox.length).toBeGreaterThan(0);
		// Bun reuses the message handler's backing buffer for the next frame; the
		// relay must copy anything it defers, so mutating the source after the
		// call must not change what eventually gets delivered.
		const reused = Buffer.alloc(FRAME, 7);
		forwardFrame(guest.socket, reused);
		reused.fill(0);
		let guard = 0;
		while (guest.outbox.length > 0 && guard++ < 20)
			guest.drain(SOCKET_SEND_HIGH_WATER_BYTES);
		const delivered = guest.sent[guest.sent.length - 1]!;
		expect(delivered.every((byte) => byte === 7)).toBe(true);
	});

	it("retains a frame the socket refuses (send() === 0) until it drains", () => {
		let accept = false;
		const sent: Buffer[] = [];
		const fake = {
			data: { outbox: [] as (string | Buffer)[] },
			getBufferedAmount: () => 0,
			send(message: Buffer): number {
				if (!accept) return 0;
				sent.push(Buffer.from(message));
				return message.byteLength;
			},
		};
		const socket = fake as unknown as Parameters<typeof forwardFrame>[0];
		const frame = Buffer.alloc(1024, 9);
		forwardFrame(socket, frame);
		// The socket refused the frame (returned 0); it must be kept, not dropped.
		expect(fake.data.outbox.length).toBe(1);
		expect(sent.length).toBe(0);
		// Once the socket accepts again, drain redelivers it byte-for-byte.
		accept = true;
		pumpOutbox(socket);
		expect(fake.data.outbox.length).toBe(0);
		expect(sent).toHaveLength(1);
		expect(sent[0]!.equals(frame)).toBe(true);
	});
});
