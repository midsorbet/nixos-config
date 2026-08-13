const root = document.getElementById("root");

const REFRESH_INTERVAL_MS = 5000;
const MAX_ACTIVATION_ATTEMPTS = 3;
const ACTIVATION_RETRY_DELAY_MS = 1200;

async function responseError(response, fallback) {
	try {
		const body = await response.json();
		if (typeof body.error === "string" && body.error.trim()) return body.error;
	} catch {
		// The status code below is still useful when a proxy returns a non-JSON error.
	}
	return `${fallback} (${response.status})`;
}

function delay(milliseconds) {
	return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function brand() {
	const element = document.createElement("a");
	element.className = "rooms-brand";
	element.href = "/";
	element.setAttribute("aria-label", "OMP agent dashboard");
	element.innerHTML =
		'<span class="rooms-mark" aria-hidden="true"></span><span class="rooms-pi" aria-hidden="true">π</span> omp remote';
	return element;
}

function actionButton(label, className = "rooms-button") {
	const button = document.createElement("button");
	button.type = "button";
	button.className = className;
	button.textContent = label;
	return button;
}

function statusLabel(value) {
	if (value === "working") return "Working";
	if (value === "blocked") return "Blocked";
	return "Idle";
}

function agentCard(agent) {
	const card = document.createElement("a");
	card.className = "rooms-card";
	card.href = `/open/${encodeURIComponent(agent.id)}`;
	card.target = "_blank";
	card.rel = "noopener";
	card.setAttribute(
		"aria-label",
		`Open ${agent.label || "OMP agent"} in a new tab`,
	);

	const top = document.createElement("span");
	top.className = "rooms-card-top";

	const status = document.createElement("span");
	const state = ["working", "idle", "blocked"].includes(agent.status)
		? agent.status
		: "idle";
	status.className = `rooms-status rooms-status-${state}`;
	status.textContent = statusLabel(state);
	top.append(status);

	if (agent.focused) {
		const focused = document.createElement("span");
		focused.className = "rooms-badge";
		focused.textContent = "Focused";
		top.append(focused);
	}

	const title = document.createElement("strong");
	title.textContent = agent.label || "OMP agent";

	const cwd = document.createElement("span");
	cwd.className = "rooms-cwd";
	cwd.textContent = agent.cwd || "Working directory unavailable";
	cwd.title = agent.cwd || "";

	const meta = document.createElement("span");
	meta.className = "rooms-meta";
	meta.textContent = agent.remoteCached
		? "Remote ready · opens in a new tab"
		: "Remote starts when opened";

	const arrow = document.createElement("span");
	arrow.className = "rooms-arrow";
	arrow.setAttribute("aria-hidden", "true");
	arrow.textContent = "Open ↗";

	card.append(top, title, cwd, meta, arrow);
	return card;
}

function messagePanel(title, detail, tone = "") {
	const panel = document.createElement("div");
	panel.className = `rooms-empty${tone ? ` rooms-${tone}` : ""}`;

	const heading = document.createElement("strong");
	heading.textContent = title;
	const description = document.createElement("span");
	description.textContent = detail;
	panel.append(heading, description);
	return panel;
}

function renderService(service, element) {
	const status = service?.status || "unavailable";
	const schedule = service?.schedule;
	const statusText =
		{
			available: "Service available",
			"outside-schedule": "Outside scheduled hours",
			stopping: "Service stopping",
		}[status] || "Service status unavailable";

	let detail = "";
	if (schedule?.start && schedule?.stop) {
		const timezone = schedule.timezone ? ` ${schedule.timezone}` : "";
		detail = `Weekdays ${schedule.start}–${schedule.stop}${timezone}`;
	}
	if (service?.manualOverrideUntil) {
		const until = new Date(service.manualOverrideUntil);
		if (!Number.isNaN(until.getTime())) {
			detail = `Manual window until ${until.toLocaleTimeString([], {
				hour: "numeric",
				minute: "2-digit",
			})}`;
		}
	}

	element.className = `rooms-service rooms-service-${status}`;
	element.replaceChildren();
	const dot = document.createElement("span");
	dot.className = "rooms-service-dot";
	dot.setAttribute("aria-hidden", "true");
	const copy = document.createElement("span");
	const strong = document.createElement("strong");
	strong.textContent = statusText;
	copy.append(strong);
	if (detail) {
		const scheduleText = document.createElement("small");
		scheduleText.textContent = detail;
		copy.append(scheduleText);
	}
	element.append(dot, copy);
}

function dashboardMarkup() {
	root.replaceChildren();
	const shell = document.createElement("main");
	shell.className = "rooms-shell";
	shell.innerHTML = `
		<header class="rooms-header">
			<div class="rooms-masthead">
				<div class="rooms-brand-slot"></div>
				<div class="rooms-service" aria-live="polite">
					<span class="rooms-service-dot" aria-hidden="true"></span>
					<span><strong>Checking service…</strong></span>
				</div>
			</div>
			<div>
				<p class="rooms-eyebrow">REMOTE WORKSPACE</p>
				<h1>OMP agents on the Mini</h1>
				<p class="rooms-subtitle">Open an active agent, or start a fresh one rooted in the vault.</p>
			</div>
			<div class="rooms-toolbar">
				<span class="rooms-count" aria-live="polite">Loading agents…</span>
				<div class="rooms-actions">
					<button class="rooms-button rooms-refresh" type="button">Refresh</button>
					<button class="rooms-button rooms-new" type="button">New OMP agent</button>
				</div>
			</div>
		</header>
		<section class="rooms-list" aria-label="Active OMP agents" aria-busy="true"></section>`;
	shell.querySelector(".rooms-brand-slot").replaceWith(brand());
	root.append(shell);
}

async function runDashboard() {
	document.title = "OMP agents — remote dashboard";
	dashboardMarkup();

	const list = document.querySelector(".rooms-list");
	const count = document.querySelector(".rooms-count");
	const refreshButton = document.querySelector(".rooms-refresh");
	const newButton = document.querySelector(".rooms-new");
	const serviceElement = document.querySelector(".rooms-service");
	let refreshing = false;
	let creating = false;

	async function refreshService() {
		try {
			const response = await fetch("/api/service", { cache: "no-store" });
			if (!response.ok) {
				throw new Error(
					await responseError(response, "Service status unavailable"),
				);
			}
			renderService(await response.json(), serviceElement);
		} catch {
			renderService(null, serviceElement);
		}
	}

	async function refreshAgents({ showLoading = false } = {}) {
		if (refreshing) return;
		refreshing = true;
		refreshButton.disabled = true;
		refreshButton.textContent = "Refreshing…";
		if (showLoading) {
			list.setAttribute("aria-busy", "true");
			list.replaceChildren(
				messagePanel("Finding OMP agents", "Checking the Mini now…", "loading"),
			);
		}

		try {
			const response = await fetch("/api/agents", { cache: "no-store" });
			if (!response.ok) {
				throw new Error(
					await responseError(response, "Agent list unavailable"),
				);
			}
			const agents = await response.json();
			if (!Array.isArray(agents))
				throw new Error("Agent list returned invalid data");

			count.textContent = `${agents.length} active ${agents.length === 1 ? "agent" : "agents"}`;
			list.replaceChildren();
			if (agents.length === 0) {
				const empty = messagePanel(
					"No active OMP agents",
					"Start one here and it will appear as soon as OMP launches.",
				);
				const create = actionButton("New OMP agent");
				create.addEventListener("click", createAgent);
				empty.append(create);
				list.append(empty);
			} else {
				for (const agent of agents) list.append(agentCard(agent));
			}
		} catch (error) {
			count.textContent = "Agent list unavailable";
			const failure = messagePanel(
				"Couldn’t load OMP agents",
				error instanceof Error ? error.message : String(error),
				"error",
			);
			const retry = actionButton("Try again");
			retry.addEventListener("click", () =>
				refreshAgents({ showLoading: true }),
			);
			failure.append(retry);
			list.replaceChildren(failure);
		} finally {
			list.setAttribute("aria-busy", "false");
			refreshing = false;
			refreshButton.disabled = false;
			refreshButton.textContent = "Refresh";
		}
	}

	async function createAgent() {
		if (creating) return;
		creating = true;
		newButton.disabled = true;
		newButton.textContent = "Starting…";
		count.textContent = "Starting a new OMP agent…";
		try {
			const response = await fetch("/api/agents", {
				method: "POST",
				headers: { Accept: "application/json" },
			});
			if (!response.ok) {
				throw new Error(
					await responseError(response, "Couldn’t start an agent"),
				);
			}
			await response.json();
			await refreshAgents();
		} catch (error) {
			count.textContent =
				error instanceof Error ? error.message : "Couldn’t start an agent";
		} finally {
			creating = false;
			newButton.disabled = false;
			newButton.textContent = "New OMP agent";
		}
	}

	refreshButton.addEventListener("click", () =>
		Promise.all([refreshAgents({ showLoading: true }), refreshService()]),
	);
	newButton.addEventListener("click", createAgent);
	await Promise.all([refreshAgents({ showLoading: true }), refreshService()]);

	window.setInterval(() => {
		if (document.visibilityState === "visible") {
			void Promise.all([refreshAgents(), refreshService()]);
		}
	}, REFRESH_INTERVAL_MS);
}

function loadingMarkup(paneId) {
	root.replaceChildren();
	const shell = document.createElement("main");
	shell.className = "rooms-shell rooms-open-shell";
	shell.innerHTML = `
		<div class="rooms-brand-slot"></div>
		<section class="rooms-open" aria-labelledby="open-title">
			<div class="rooms-spinner" aria-hidden="true"></div>
			<p class="rooms-eyebrow">SECURE REMOTE SESSION</p>
			<h1 id="open-title">Opening your agent</h1>
			<p class="rooms-open-detail" aria-live="polite">Preparing full-control access on the Mini…</p>
			<p class="rooms-attempt" aria-live="polite"></p>
			<div class="rooms-open-actions"></div>
		</section>`;
	shell.querySelector(".rooms-brand-slot").replaceWith(brand());
	root.append(shell);
	document.title = "Opening OMP agent…";

	const detail = shell.querySelector(".rooms-open-detail");
	const attemptText = shell.querySelector(".rooms-attempt");
	const actions = shell.querySelector(".rooms-open-actions");
	const spinner = shell.querySelector(".rooms-spinner");
	let run = 0;

	async function activate() {
		run += 1;
		actions.replaceChildren();
		spinner.hidden = false;
		detail.textContent = "Preparing full-control access on the Mini…";

		let lastError = "The agent could not be opened.";
		for (let attempt = 1; attempt <= MAX_ACTIVATION_ATTEMPTS; attempt += 1) {
			attemptText.textContent =
				attempt === 1
					? "Contacting the agent…"
					: `Retrying… ${attempt} of ${MAX_ACTIVATION_ATTEMPTS}`;
			try {
				const response = await fetch(`/api/agents/${paneId}/activate`, {
					method: "POST",
					headers: { Accept: "application/json" },
					cache: "no-store",
				});
				if (!response.ok) {
					throw new Error(await responseError(response, "Activation failed"));
				}
				const body = await response.json();
				if (typeof body.link !== "string") {
					throw new Error("Activation returned an invalid destination");
				}
				const destination = new URL(body.link);
				if (
					destination.protocol !== "https:" ||
					destination.host !== window.location.host ||
					!destination.hash.slice(1)
				) {
					throw new Error("Activation returned an unsafe destination");
				}
				window.location.replace(destination.href);
				return;
			} catch (error) {
				lastError = error instanceof Error ? error.message : String(error);
				if (attempt < MAX_ACTIVATION_ATTEMPTS) {
					await delay(ACTIVATION_RETRY_DELAY_MS);
				}
			}
		}

		if (run <= 0) return;
		spinner.hidden = true;
		document.title = "Couldn’t open OMP agent";
		detail.textContent = lastError;
		attemptText.textContent =
			"The agent may have closed or the remote service may still be starting.";
		const retry = actionButton("Retry");
		retry.addEventListener("click", activate);
		const dashboard = document.createElement("a");
		dashboard.className = "rooms-button rooms-button-secondary";
		dashboard.href = "/";
		dashboard.textContent = "Back to agents";
		actions.append(retry, dashboard);
	}

	void activate();
}

const openMatch = window.location.pathname.match(/^\/open\/([^/]+)\/?$/);
if (openMatch) {
	loadingMarkup(openMatch[1]);
} else {
	await runDashboard();
}
