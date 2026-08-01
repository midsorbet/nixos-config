import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const START_COMMAND = "@startCommand@";
const STOP_COMMAND = "@stopCommand@";
const STATUS_COMMAND = "@statusCommand@";

export default function (pi: ExtensionAPI) {
	let ownsExposure = false;

	const run = async (command: string): Promise<{ ok: boolean; stdout: string; error: string }> => {
		const result = await pi.exec(command, []);
		return {
			ok: result.code === 0,
			stdout: result.stdout.trim(),
			error: (result.stderr.trim() || result.stdout.trim() || `${command} exited ${result.code}`).trim(),
		};
	};

	pi.registerCommand("remote-collab", {
		description: "Start, inspect, or stop the on-demand omp.midsorbet.me collab relay",
		getArgumentCompletions(argumentPrefix) {
			if (argumentPrefix.includes(" ")) return null;
			const prefix = argumentPrefix.trim().toLowerCase();
			const items = [
				{ label: "view", value: "view", description: "Start or show a read-only browser link" },
				{ label: "status", value: "status", description: "Show relay and tunnel health" },
				{ label: "stop", value: "stop", description: "End collab and remove public exposure" },
			];
			const filtered = items.filter(item => item.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const action = args.trim().toLowerCase();
			if (action === "status") {
				const status = await run(STATUS_COMMAND);
				ctx.ui.notify(status.ok ? status.stdout : status.error, status.ok ? "info" : "error");
				return;
			}
			if (action === "stop") {
				const stopped = await run(STOP_COMMAND);
				if (!stopped.ok) {
					ctx.ui.notify(stopped.error, "error");
					return;
				}
				ownsExposure = false;
				ctx.ui.notify(stopped.stdout || "Remote collab stopped", "info");
				return;
			}
			if (action !== "" && action !== "view") {
				ctx.ui.notify("Usage: /remote-collab [view|status|stop]", "error");
				return;
			}

			ctx.ui.notify("Starting the on-demand OMP collab tunnel…", "info");
			const started = await run(START_COMMAND);
			if (!started.ok) {
				ctx.ui.notify(started.error, "error");
				return;
			}
			if (started.stdout.includes("OMP_COLLAB_STARTED=1")) ownsExposure = true;
			pi.sendUserMessage("/collab view", { deliverAs: "followUp" });
		},
	});

	pi.on("session_shutdown", async () => {
		if (!ownsExposure) return;
		ownsExposure = false;
		await pi.exec(STOP_COMMAND, []);
	});
}
