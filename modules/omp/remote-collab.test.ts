import { describe, expect, it, mock } from "bun:test";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

class MockCollabHost {
	webViewLink =
		"https://omp.midsorbet.me/#ws://127.0.0.1:17475/r/TestRoom_12345.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
	async start(): Promise<void> {}
	async stop(): Promise<void> {}
}

mock.module("@oh-my-pi/pi-coding-agent/collab/host", () => ({
	CollabHost: MockCollabHost,
}));
// Dynamic import is intentional: Bun must install the runtime module mock before evaluating the extension.
const { default: registerRemoteCollab } = await import("./remote-collab");

interface TestContext {
	cwd: string;
	ui: {
		notify(message: string): void;
		setEditorText(value: string): void;
	};
}

type InputHandler = (
	event: { source: string; text: string },
	ctx: TestContext,
) => unknown | Promise<unknown>;

interface CommandDefinition {
	getArgumentCompletions(prefix: string): Array<{ value: string }> | null;
	handler(args: string, ctx: TestContext): Promise<void> | void;
}

function createHarness() {
	let handleInput: InputHandler | null = null;
	let command: CommandDefinition | null = null;
	const editorValues: string[] = [];
	const notifications: string[] = [];
	const execCalls: string[] = [];

	const pi = {
		getSessionName: () => "parallel room",
		exec: async (executable: string) => {
			execCalls.push(executable);
			return { code: 0, stdout: "OMP_COLLAB_STARTED=1\n", stderr: "" };
		},
		on: (event: string, handler: InputHandler) => {
			if (event === "input") handleInput = handler;
		},
		registerCommand: (_name: string, definition: CommandDefinition) => {
			command = definition;
		},
	};
	// The test double implements exactly the ExtensionAPI surface used by this extension.
	registerRemoteCollab(pi as unknown as ExtensionAPI);

	const ctx: TestContext = {
		cwd: "/Users/me/vault/projects/nixos-config",
		ui: {
			notify: (message: string) => notifications.push(message),
			setEditorText: (value: string) => editorValues.push(value),
		},
	};

	return {
		command: () => {
			if (!command) throw new Error("remote-collab command was not registered");
			return command;
		},
		ctx,
		editorValues,
		inputHandler: () => {
			if (!handleInput)
				throw new Error("remote-collab input handler was not registered");
			return handleInput;
		},
		execCalls,
		notifications,
	};
}

describe("remote-collab sharing modes", () => {
	it("makes writable full-control sharing the interactive default", async () => {
		const harness = createHarness();
		const handleInput = harness.inputHandler();

		for (const text of ["/remote-collab", "/remote-collab write"]) {
			const result = await handleInput(
				{ source: "interactive", text },
				harness.ctx,
			);
			expect(result).toEqual({ text: "/collab" });
		}
		expect(harness.execCalls).toHaveLength(2);
	});

	it("registers the generated read-only link for the room dashboard", async () => {
		const originalFetch = globalThis.fetch;
		let registration: Record<string, unknown> | null = null;
		globalThis.fetch = (async (
			_input: string | URL | Request,
			init?: RequestInit,
		) => {
			registration = JSON.parse(String(init?.body));
			return new Response(null, { status: 204 });
		}) as typeof fetch;
		try {
			const harness = createHarness();
			await harness.inputHandler()(
				{ source: "interactive", text: "/remote-collab view" },
				harness.ctx,
			);
			await new MockCollabHost().start();
			expect(registration).toEqual({
				link: expect.stringContaining("TestRoom_12345"),
				label: "parallel room",
				cwd: "/Users/me/vault/projects/nixos-config",
			});
		} finally {
			globalThis.fetch = originalFetch;
		}
	});

	it("preserves an explicit read-only browser mode", async () => {
		const harness = createHarness();
		const handleInput = harness.inputHandler();
		const result = await handleInput(
			{ source: "interactive", text: "/remote-collab view" },
			harness.ctx,
		);
		expect(result).toEqual({ text: "/collab view" });
	});

	it("prepares session-scoped stop and explicit relay shutdown commands", async () => {
		const harness = createHarness();
		await harness.command().handler("", harness.ctx);
		await harness.command().handler("write", harness.ctx);
		await harness.command().handler("view", harness.ctx);
		await harness.command().handler("stop", harness.ctx);
		await harness.command().handler("shutdown", harness.ctx);

		expect(harness.editorValues).toEqual([
			"/collab",
			"/collab",
			"/collab view",
			"/collab stop",
		]);
		expect(harness.notifications.at(-2)).toContain("stop sharing this session");
		expect(
			harness
				.command()
				.getArgumentCompletions("")
				?.map((item) => item.value),
		).toEqual(["write", "view", "status", "stop", "shutdown"]);
	});
});
