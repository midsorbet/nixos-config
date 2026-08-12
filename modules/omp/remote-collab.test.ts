import { describe, expect, it } from "bun:test";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import registerRemoteCollab from "./remote-collab";

interface TestContext {
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
			if (!handleInput) throw new Error("remote-collab input handler was not registered");
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
			const result = await handleInput({ source: "interactive", text }, harness.ctx);
			expect(result).toEqual({ text: "/collab" });
		}
		expect(harness.execCalls).toHaveLength(2);
	});

	it("preserves an explicit read-only browser mode", async () => {
		const harness = createHarness();
		const handleInput = harness.inputHandler();
		const result = await handleInput({ source: "interactive", text: "/remote-collab view" }, harness.ctx);
		expect(result).toEqual({ text: "/collab view" });
	});

	it("prepares the matching upstream collab command", async () => {
		const harness = createHarness();
		await harness.command().handler("", harness.ctx);
		await harness.command().handler("write", harness.ctx);
		await harness.command().handler("view", harness.ctx);

		expect(harness.editorValues).toEqual(["/collab", "/collab", "/collab view"]);
		expect(harness.notifications.at(-1)).toContain("read-only");
		expect(harness.command().getArgumentCompletions("")?.map(item => item.value)).toEqual([
			"write",
			"view",
			"status",
			"stop",
		]);
	});
});
