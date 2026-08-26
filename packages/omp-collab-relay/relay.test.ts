import { afterEach, describe, expect, it } from "bun:test";
import {
	type CollabRelay,
	type HerdrDashboard,
	type HerdrPane,
	type HerdrSubscription,
	type HerdrTransport,
	createHerdrDashboard,
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
