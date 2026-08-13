import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const START_COMMAND = "@startCommand@";
const STOP_COMMAND = "@stopCommand@";
const STATUS_COMMAND = "@statusCommand@";

const runCommand = async (
	pi: ExtensionAPI,
	command: string,
): Promise<{ ok: boolean; stdout: string; error: string }> => {
	const result = await pi.exec(command, []);
	return {
		ok: result.code === 0,
		stdout: result.stdout.trim(),
		error: (
			result.stderr.trim() ||
			result.stdout.trim() ||
			`${command} exited ${result.code}`
		).trim(),
	};
};

export default function (pi: ExtensionAPI) {
	const startExposure = async (ctx: ExtensionContext): Promise<boolean> => {
		ctx.ui.notify("Starting the OMP remote dashboard…", "info");
		const started = await runCommand(pi, START_COMMAND);
		if (started.ok) return true;
		ctx.ui.notify(started.error, "error");
		return false;
	};
	const showStatus = async (ctx: ExtensionContext): Promise<void> => {
		const status = await runCommand(pi, STATUS_COMMAND);
		ctx.ui.notify(
			status.ok ? status.stdout : status.error,
			status.ok ? "info" : "error",
		);
	};
	const stopExposure = async (ctx: ExtensionContext): Promise<void> => {
		const stopped = await runCommand(pi, STOP_COMMAND);
		ctx.ui.notify(
			stopped.ok ? stopped.stdout : stopped.error,
			stopped.ok ? "info" : "error",
		);
	};

	pi.on("input", async (event, ctx) => {
		if (event.source !== "interactive") return;
		const input = event.text.trim().toLowerCase();
		const action =
			input === "/remote-collab"
				? ""
				: input.startsWith("/remote-collab ")
					? input.slice(15).trim()
					: null;
		if (action === null) return;
		if (action === "stop") return { text: "/collab stop" };
		if (action === "status") {
			await showStatus(ctx);
			return { handled: true };
		}
		if (action === "shutdown") {
			await stopExposure(ctx);
			return { handled: true };
		}
		if (action !== "" && action !== "write") return;
		if (!(await startExposure(ctx))) return { handled: true };
		return { text: "/collab" };
	});

	pi.registerCommand("remote-collab", {
		description:
			"Open full-control access through the omp.midsorbet.me remote dashboard",
		getArgumentCompletions(argumentPrefix) {
			if (argumentPrefix.includes(" ")) return null;
			const prefix = argumentPrefix.trim().toLowerCase();
			const items = [
				{
					label: "write",
					value: "write",
					description: "Open a full-control browser link",
				},
				{
					label: "status",
					value: "status",
					description: "Show relay and tunnel health",
				},
				{
					label: "stop",
					value: "stop",
					description: "Stop sharing this OMP session",
				},
				{
					label: "shutdown",
					value: "shutdown",
					description: "Stop the shared remote dashboard service",
				},
			];
			const filtered = items.filter((item) => item.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const action = args.trim().toLowerCase();
			if (action === "status") {
				await showStatus(ctx);
				return;
			}
			if (action === "stop") {
				ctx.ui.setEditorText("/collab stop");
				ctx.ui.notify("Press Enter to stop sharing this session", "info");
				return;
			}
			if (action === "shutdown") {
				await stopExposure(ctx);
				return;
			}
			if (action !== "" && action !== "write") {
				ctx.ui.notify(
					"Usage: /remote-collab [write|status|stop|shutdown]",
					"error",
				);
				return;
			}
			if (!(await startExposure(ctx))) return;
			ctx.ui.setEditorText("/collab");
			ctx.ui.notify(
				"Press Enter to open the full-control browser link",
				"info",
			);
		},
	});
}
