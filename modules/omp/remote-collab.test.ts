import { describe, expect, it } from "bun:test";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import registerRemoteCollab from "./remote-collab";

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
		exec: async (executable: string) => {
			execCalls.push(executable);
			return { code: 0, stdout: "ready\n", stderr: "" };
		},
		on: (event: string, handler: InputHandler) => {
			if (event === "input") handleInput = handler;
		},
		registerCommand: (_name: string, definition: CommandDefinition) => {
			command = definition;
		},
	};
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

describe("remote-collab commands", () => {
	it("turns an interactive activation into one writable collab submission", async () => {
		const harness = createHarness();
		for (const text of ["/remote-collab", "/remote-collab write"]) {
			expect(
				await harness.inputHandler()(
					{ source: "interactive", text },
					harness.ctx,
				),
			).toEqual({ text: "/collab" });
		}
		expect(harness.execCalls).toHaveLength(2);
	});

	it("does not expose a dashboard read-only mode", async () => {
		const harness = createHarness();
		expect(
			await harness.inputHandler()(
				{ source: "interactive", text: "/remote-collab view" },
				harness.ctx,
			),
		).toBeUndefined();
		expect(harness.execCalls).toHaveLength(0);
	});

	it("separates session stop from service shutdown", async () => {
		const harness = createHarness();
		await harness.command().handler("", harness.ctx);
		await harness.command().handler("write", harness.ctx);
		await harness.command().handler("stop", harness.ctx);
		await harness.command().handler("shutdown", harness.ctx);
		expect(harness.editorValues).toEqual([
			"/collab",
			"/collab",
			"/collab stop",
		]);
		expect(harness.notifications.at(-2)).toContain("stop sharing this session");
		expect(
			harness
				.command()
				.getArgumentCompletions("")
				?.map((item) => item.value),
		).toEqual(["write", "status", "stop", "shutdown"]);
	});
});
