import { CollabHost } from "@oh-my-pi/pi-coding-agent/collab/host";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const START_COMMAND = "@startCommand@";
const STOP_COMMAND = "@stopCommand@";
const STATUS_COMMAND = "@statusCommand@";
const REGISTER_URL = "@registerUrl@";

type ShareMode = "write" | "view";

let registrationContext: { cwd: string } = { cwd: "" };
const originalStart = CollabHost.prototype.start;
let registrationInstalled = false;

const parseShareMode = (action: string): ShareMode | null => {
	if (action === "" || action === "write") return "write";
	if (action === "view") return "view";
	return null;
};

const collabCommand = (mode: ShareMode): string =>
	mode === "write" ? "/collab" : "/collab view";

function installRoomRegistration(pi: ExtensionAPI): void {
	if (registrationInstalled) return;
	registrationInstalled = true;
	CollabHost.prototype.start = async function (...args): Promise<void> {
		await originalStart.apply(this, args);
		const cwd = registrationContext.cwd;
		const fallback = cwd.split("/").filter(Boolean).at(-1) || "OMP session";
		const response = await fetch(REGISTER_URL, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				link: this.webViewLink,
				label: pi.getSessionName() || fallback,
				cwd,
			}),
		});
		if (!response.ok) {
			console.error(
				`remote-collab: room directory registration failed (${response.status})`,
			);
		}
	};
}

export default function (pi: ExtensionAPI) {
	installRoomRegistration(pi);

	const run = async (
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
	const startExposure = async (ctx: ExtensionContext): Promise<boolean> => {
		registrationContext = { cwd: ctx.cwd };
		ctx.ui.notify("Starting the on-demand OMP collab tunnel…", "info");
		const started = await run(START_COMMAND);
		if (started.ok) return true;
		ctx.ui.notify(started.error, "error");
		return false;
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
			const status = await run(STATUS_COMMAND);
			ctx.ui.notify(
				status.ok ? status.stdout : status.error,
				status.ok ? "info" : "error",
			);
			return { handled: true };
		}
		if (action === "shutdown") {
			const stopped = await run(STOP_COMMAND);
			ctx.ui.notify(
				stopped.ok ? stopped.stdout : stopped.error,
				stopped.ok ? "info" : "error",
			);
			return { handled: true };
		}
		const mode = parseShareMode(action);
		if (mode === null) return;
		if (!(await startExposure(ctx))) return { handled: true };
		return { text: collabCommand(mode) };
	});

	pi.registerCommand("remote-collab", {
		description:
			"Share this OMP session through the on-demand omp.midsorbet.me room dashboard",
		getArgumentCompletions(argumentPrefix) {
			if (argumentPrefix.includes(" ")) return null;
			const prefix = argumentPrefix.trim().toLowerCase();
			const items = [
				{
					label: "write",
					value: "write",
					description: "Start or show a full-control browser link",
				},
				{
					label: "view",
					value: "view",
					description: "Start or show a read-only browser link",
				},
				{
					label: "status",
					value: "status",
					description: "Show relay and tunnel health",
				},
				{
					label: "stop",
					value: "stop",
					description: "Stop sharing this session",
				},
				{
					label: "shutdown",
					value: "shutdown",
					description: "Stop every room and remove public exposure",
				},
			];
			const filtered = items.filter((item) => item.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const action = args.trim().toLowerCase();
			if (action === "status") {
				const status = await run(STATUS_COMMAND);
				ctx.ui.notify(
					status.ok ? status.stdout : status.error,
					status.ok ? "info" : "error",
				);
				return;
			}
			if (action === "stop") {
				ctx.ui.setEditorText("/collab stop");
				ctx.ui.notify("Press Enter to stop sharing this session", "info");
				return;
			}
			if (action === "shutdown") {
				const stopped = await run(STOP_COMMAND);
				ctx.ui.notify(
					stopped.ok ? stopped.stdout : stopped.error,
					stopped.ok ? "info" : "error",
				);
				return;
			}
			const mode = parseShareMode(action);
			if (mode === null) {
				ctx.ui.notify(
					"Usage: /remote-collab [write|view|status|stop|shutdown]",
					"error",
				);
				return;
			}
			if (!(await startExposure(ctx))) return;
			ctx.ui.setEditorText(collabCommand(mode));
			ctx.ui.notify(
				`Press Enter to open the ${mode === "write" ? "full-control" : "read-only"} collab browser link`,
				"info",
			);
		},
	});
}
