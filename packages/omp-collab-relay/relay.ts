import { existsSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import type {
	RelayControlToGuest,
	RelayControlToHost,
} from "@oh-my-pi/pi-wire";
import { ENVELOPE_HEADER_LENGTH } from "@oh-my-pi/pi-wire";

export const ROOM_PATH_RE = /^\/r\/([A-Za-z0-9_-]{10,64})$/;
const ROOM_LINK_PATH_RE = /^\/r\/([A-Za-z0-9_-]{10,64})\.([A-Za-z0-9_-]+)$/;
const RENDERED_COLLAB_LINK_START_RE =
	/(?:https?:\/\/)?(?:[A-Za-z0-9.-]+|\[[A-Fa-f0-9:]+\])(?::\d+)?\/#(?:wss?|ws):\/\//;
const RENDERED_COLLAB_LINK_RE =
	/(?:https?:\/\/)?(?:[A-Za-z0-9.-]+|\[[A-Fa-f0-9:]+\])(?::\d+)?\/#(?:wss?|ws):\/\/\S+/g;
const MAX_RENDERED_COLLAB_LINK_LINES = 8;

/** Reassembles browser links hard-wrapped across rows by narrow TUI panes. */
function renderedCollabLinkCandidates(text: string): string[] {
	const lines = text.split("\n");
	const candidates: string[] = [];
	for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
		const line = lines[lineIndex]!;
		const start = line.search(RENDERED_COLLAB_LINK_START_RE);
		if (start < 0) continue;
		const wrapWidth = line.length;
		let joined = line.slice(start).trimEnd();
		for (let offset = 0; offset < MAX_RENDERED_COLLAB_LINK_LINES; offset++) {
			candidates.push(...(joined.match(RENDERED_COLLAB_LINK_RE) ?? []));
			const sourceLine = lines[lineIndex + offset];
			const continuation = lines[lineIndex + offset + 1];
			if (!sourceLine || !continuation || sourceLine.length !== wrapWidth)
				break;
			joined += continuation.trimStart();
		}
	}
	return candidates;
}
const PROTOCOL_MAX_FRAME_BYTES = 16 * 1024 * 1024;
const LOADING_HTML = `<!doctype html><meta charset="utf-8"><title>Opening OMP agent</title><p>Opening agent…</p><script>fetch(location.pathname.replace(/^\\/open\\//,'/api/agents/')+'/activate',{method:'POST',headers:{'X-Requested-With':'omp-dashboard'}}).then(async r=>{if(!r.ok)throw new Error(await r.text());return r.json()}).then(x=>location.replace(x.link)).catch(e=>{document.body.innerHTML='<p>Unable to open agent: '+String(e.message||e)+'</p><button onclick="location.reload()">Retry</button>'})</script>`;

export type AgentStatus = "working" | "idle" | "blocked";

export interface DashboardAgent {
	id: string;
	label: string;
	cwd: string;
	status: AgentStatus;
	focused: boolean;
	remoteCached: boolean;
}

export interface AgentSessionReference {
	source: string;
	agent: string;
	kind: "id" | "path";
	value: string;
}

export interface HerdrPane {
	id: string;
	identity: string;
	session: AgentSessionReference;
	label: string;
	cwd: string;
	status: AgentStatus;
	focused: boolean;
}

export interface HerdrWireRequest {
	id: string;
	method: string;
	params: Record<string, unknown>;
}

export interface HerdrSubscription {
	close(): void;
}

export interface HerdrTransport {
	request(request: HerdrWireRequest): Promise<unknown>;
	subscribe(
		request: HerdrWireRequest,
		onEvent: (event: unknown) => void,
		onClose: (error?: Error) => void,
	): Promise<HerdrSubscription>;
}
export interface HerdrDashboardOptions {
	socketPath: string;
	vaultRoot: string;
	activationTimeoutMs: number;
	reconnectDelayMs: number;
	pluginId: string;
	pluginEntrypoint: string;
	transport?: HerdrTransport;
	sleep?: (milliseconds: number) => Promise<void>;
}

const HERDR_MAX_LINE_BYTES = 1024 * 1024;
const HERDR_SUBSCRIPTIONS = [
	{ type: "pane.created" },
	{ type: "pane.updated" },
	{ type: "pane.closed" },
	{ type: "pane.focused" },
	{ type: "pane.moved" },
	{ type: "pane.exited" },
	{ type: "pane.agent_detected" },
] as const;

function object(value: unknown): Record<string, unknown> | null {
	return typeof value === "object" && value !== null
		? (value as Record<string, unknown>)
		: null;
}

function nonEmptyString(value: unknown): string | null {
	return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function herdrResult(
	value: unknown,
	expectedType: string,
): Record<string, unknown> {
	const envelope = object(value);
	const error = envelope ? object(envelope.error) : null;
	if (error)
		throw new Error(nonEmptyString(error.message) ?? "Herdr request failed");
	const result = envelope ? object(envelope.result) : null;
	if (!result || result.type !== expectedType)
		throw new Error(`Herdr returned an invalid ${expectedType} response`);
	return result;
}

function statusOf(value: unknown): AgentStatus {
	if (value === "working" || value === "blocked") return value;
	return "idle";
}

function parseSession(value: unknown): AgentSessionReference | null {
	const session = object(value);
	const source = session ? nonEmptyString(session.source) : null;
	const agent = session ? nonEmptyString(session.agent) : null;
	const kind = session?.kind;
	const reference = session ? nonEmptyString(session.value) : null;
	if (!source || !agent || (kind !== "id" && kind !== "path") || !reference)
		return null;
	return { source, agent, kind, value: reference };
}

function sessionIdentity(session: AgentSessionReference): string {
	return `${session.source}:${session.agent}:${session.kind}:${session.value}`;
}

function parseAgent(value: unknown): HerdrPane | null {
	const record = object(value);
	if (
		!record ||
		record.agent !== "omp" ||
		record.launch_pending === true ||
		record.interactive_ready === false
	)
		return null;
	const id = nonEmptyString(record.pane_id);
	const session = parseSession(record.agent_session);
	if (
		!id ||
		!session ||
		session.source !== "herdr:omp" ||
		session.agent !== "omp"
	)
		return null;
	const label =
		nonEmptyString(record.name) ??
		nonEmptyString(record.title) ??
		nonEmptyString(record.terminal_title_stripped) ??
		nonEmptyString(record.terminal_title) ??
		id;
	return {
		id,
		identity: sessionIdentity(session),
		session,
		label: label.slice(0, 120),
		cwd: (
			nonEmptyString(record.foreground_cwd) ??
			nonEmptyString(record.cwd) ??
			""
		).slice(0, 512),
		status: statusOf(record.agent_status),
		focused: record.focused === true,
	};
}

function createLineReader(
	onLine: (value: unknown) => void,
	onError: (error: Error) => void,
): (chunk: Uint8Array) => void {
	const decoder = new TextDecoder();
	let buffered = "";
	return (chunk) => {
		buffered += decoder.decode(chunk, { stream: true });
		if (Buffer.byteLength(buffered) > HERDR_MAX_LINE_BYTES) {
			onError(new Error("Herdr response exceeded the 1 MiB line limit"));
			return;
		}
		for (;;) {
			const newline = buffered.indexOf("\n");
			if (newline === -1) return;
			const line = buffered.slice(0, newline).trim();
			buffered = buffered.slice(newline + 1);
			if (!line) continue;
			try {
				onLine(JSON.parse(line));
			} catch {
				onError(new Error("Herdr returned invalid newline-delimited JSON"));
			}
		}
	};
}

export function createUnixHerdrTransport(
	socketPath: string,
	requestTimeoutMs = 30_000,
): HerdrTransport {
	type Socket = { write(data: string): number; end(): void };
	const connect = async (
		onLine: (value: unknown) => void,
		onClose: (error?: Error) => void,
	): Promise<Socket> => {
		let closed = false;
		let socket: Socket | undefined;
		const close = (error?: Error): void => {
			if (closed) return;
			closed = true;
			onClose(error);
		};
		const readChunk = createLineReader(onLine, (error) => {
			close(error);
			socket?.end();
		});
		socket = await Bun.connect({
			unix: socketPath,
			socket: {
				data(_socket, data): void {
					readChunk(data);
				},
				close(): void {
					close();
				},
				error(_socket, error): void {
					close(error);
				},
			},
		});
		return socket;
	};
	return {
		async request(request): Promise<unknown> {
			const response = Promise.withResolvers<unknown>();
			let socket: Socket | undefined;
			const timer = setTimeout(() => {
				response.reject(new Error("Herdr request timed out"));
				socket?.end();
			}, requestTimeoutMs);
			try {
				socket = await connect(
					(value) => {
						response.resolve(value);
						socket?.end();
					},
					(error) =>
						response.reject(
							error ?? new Error("Herdr closed the request socket"),
						),
				);
				socket.write(`${JSON.stringify(request)}\n`);
			} catch (error) {
				response.reject(error);
			}
			return response.promise.finally(() => clearTimeout(timer));
		},
		async subscribe(request, onEvent, onClose): Promise<HerdrSubscription> {
			const acknowledged = Promise.withResolvers<void>();
			let started = false;
			let socket: Socket | undefined;
			const timer = setTimeout(() => {
				acknowledged.reject(new Error("Herdr subscription timed out"));
				socket?.end();
			}, requestTimeoutMs);
			try {
				socket = await connect(
					(value) => {
						try {
							if (!started) {
								herdrResult(value, "subscription_started");
								started = true;
								acknowledged.resolve();
								return;
							}
							onEvent(value);
						} catch (error) {
							if (!started) acknowledged.reject(error);
							else
								onClose(
									error instanceof Error ? error : new Error(String(error)),
								);
							socket?.end();
						}
					},
					(error) => {
						if (!started)
							acknowledged.reject(
								error ?? new Error("Herdr closed the subscription socket"),
							);
						else onClose(error);
					},
				);
				socket.write(`${JSON.stringify(request)}\n`);
				await acknowledged.promise.finally(() => clearTimeout(timer));
				return { close: () => socket?.end() };
			} catch (error) {
				clearTimeout(timer);
				socket?.end();
				throw error;
			}
		},
	};
}

export interface HerdrPaneOutput {
	text: string;
	revision: number;
}

export interface HerdrDashboard {
	listPanes(): Promise<HerdrPane[]>;
	createAgent(): Promise<HerdrPane>;
	promptAgent(paneId: string): Promise<void>;
	readPane(paneId: string): Promise<HerdrPaneOutput>;
	refresh(): Promise<void>;
	stop(): void;
}

export function createHerdrDashboard(
	options: HerdrDashboardOptions,
): HerdrDashboard {
	const transport =
		options.transport ??
		createUnixHerdrTransport(options.socketPath, options.activationTimeoutMs);
	const sleep = options.sleep ?? ((milliseconds) => Bun.sleep(milliseconds));
	const panes = new Map<string, HerdrPane>();
	const changes = new Set<() => void>();
	let requestSequence = 0;
	let ready = Promise.withResolvers<void>();
	let subscription: HerdrSubscription | undefined;
	let stopped = false;
	let connecting = false;
	let reconnectScheduled = false;
	let connectionEpoch = 0;
	let statusSubscriptionPaneIds = new Set<string>();

	const bounded = async <T>(promise: Promise<T>, label: string): Promise<T> => {
		const timeout = Promise.withResolvers<never>();
		const timer = setTimeout(
			() => timeout.reject(new Error(`${label} timed out`)),
			options.activationTimeoutMs,
		);
		try {
			return await Promise.race([promise, timeout.promise]);
		} finally {
			clearTimeout(timer);
		}
	};
	const request = (method: string, params: Record<string, unknown>) =>
		bounded(
			transport.request({
				id: `omp_dashboard_${++requestSequence}`,
				method,
				params,
			}),
			`Herdr ${method}`,
		);
	const notifyChanged = (): void => {
		for (const listener of changes) listener();
	};
	const replaceSnapshot = (response: unknown): void => {
		const result = herdrResult(response, "session_snapshot");
		const snapshot = object(result.snapshot);
		if (!snapshot || !Array.isArray(snapshot.agents))
			throw new Error("Herdr session snapshot omitted agents");
		const next = new Map<string, HerdrPane>();
		for (const value of snapshot.agents) {
			const pane = parseAgent(value);
			if (pane) next.set(pane.id, pane);
		}
		panes.clear();
		for (const [id, pane] of next) panes.set(id, pane);
		notifyChanged();
	};
	const refreshSnapshot = async (): Promise<void> => {
		replaceSnapshot(await request("session.snapshot", {}));
	};
	const applyEvent = (value: unknown): void => {
		const envelope = object(value);
		const data = envelope ? object(envelope.data) : null;
		const eventName =
			(data ? nonEmptyString(data.type) : null) ??
			(typeof envelope?.event === "string"
				? envelope.event.replaceAll(".", "_")
				: "");
		if (!data || !eventName) return;
		switch (eventName) {
			case "pane_created":
			case "pane_updated": {
				const rawPane = object(data.pane);
				const id = rawPane ? nonEmptyString(rawPane.pane_id) : null;
				const pane = parseAgent(rawPane);
				if (id) {
					if (pane) panes.set(id, pane);
					else panes.delete(id);
					notifyChanged();
				}
				break;
			}
			case "pane_moved": {
				const previousId = nonEmptyString(data.previous_pane_id);
				if (previousId) panes.delete(previousId);
				const pane = parseAgent(data.pane);
				if (pane) panes.set(pane.id, pane);
				notifyChanged();
				break;
			}
			case "pane_closed":
			case "pane_exited": {
				const id = nonEmptyString(data.pane_id);
				if (id && panes.delete(id)) notifyChanged();
				break;
			}
			case "pane_focused": {
				const id = nonEmptyString(data.pane_id);
				if (!id) break;
				for (const [paneId, pane] of panes)
					panes.set(paneId, { ...pane, focused: paneId === id });
				notifyChanged();
				break;
			}
			case "pane_agent_status_changed": {
				const id = nonEmptyString(data.pane_id);
				const pane = id ? panes.get(id) : undefined;
				if (pane) {
					if (data.agent !== undefined && data.agent !== "omp")
						panes.delete(id!);
					else panes.set(id!, { ...pane, status: statusOf(data.agent_status) });
					notifyChanged();
				}
				break;
			}
			case "pane_agent_detected":
				void refreshSnapshot()
					.then(() => {
						const nextIds = new Set(panes.keys());
						const changed =
							nextIds.size !== statusSubscriptionPaneIds.size ||
							[...nextIds].some((id) => !statusSubscriptionPaneIds.has(id));
						if (changed) subscription?.close();
					})
					.catch(() => {});
				break;
		}
	};
	const scheduleReconnect = (): void => {
		if (stopped || reconnectScheduled) return;
		reconnectScheduled = true;
		void sleep(options.reconnectDelayMs).then(() => {
			reconnectScheduled = false;
			void connect();
		});
	};
	const disconnected = (epoch: number): void => {
		if (stopped || epoch !== connectionEpoch) return;
		subscription = undefined;
		scheduleReconnect();
	};
	const connect = async (): Promise<void> => {
		if (stopped || subscription) return;
		if (connecting) {
			scheduleReconnect();
			return;
		}
		const epoch = ++connectionEpoch;
		const queuedEvents: unknown[] = [];
		let bootstrapped = false;
		let candidate: HerdrSubscription | undefined;
		try {
			await refreshSnapshot();
			const subscriptions = [
				...HERDR_SUBSCRIPTIONS,
				...[...panes.values()].map((pane) => ({
					type: "pane.agent_status_changed",
					pane_id: pane.id,
				})),
			];
			statusSubscriptionPaneIds = new Set(panes.keys());
			candidate = await transport.subscribe(
				{
					id: `omp_dashboard_${++requestSequence}`,
					method: "events.subscribe",
					params: { subscriptions },
				},
				(event) => {
					if (bootstrapped) applyEvent(event);
					else queuedEvents.push(event);
				},
				() => disconnected(epoch),
			);
			if (stopped || epoch !== connectionEpoch) {
				candidate.close();
				return;
			}
			subscription = candidate;
			await refreshSnapshot();
			for (const event of queuedEvents) applyEvent(event);
			bootstrapped = true;
			ready.resolve();
		} catch {
			candidate?.close();
			if (epoch === connectionEpoch) subscription = undefined;
			scheduleReconnect();
		} finally {
			connecting = false;
			if (!stopped && !subscription) scheduleReconnect();
		}
	};
	const waitForPane = async (paneId: string): Promise<HerdrPane> => {
		const existing = panes.get(paneId);
		if (existing) return existing;
		const result = Promise.withResolvers<HerdrPane>();
		const listener = (): void => {
			const pane = panes.get(paneId);
			if (pane) result.resolve(pane);
		};
		changes.add(listener);
		const timer = setTimeout(
			() =>
				result.reject(new Error("New OMP agent did not become ready in time")),
			options.activationTimeoutMs,
		);
		try {
			return await result.promise;
		} finally {
			clearTimeout(timer);
			changes.delete(listener);
		}
	};

	void connect();
	return {
		async listPanes(): Promise<HerdrPane[]> {
			await bounded(ready.promise, "Herdr dashboard readiness");
			return [...panes.values()];
		},
		async refresh(): Promise<void> {
			await bounded(ready.promise, "Herdr dashboard readiness");
			await refreshSnapshot();
		},
		async createAgent(): Promise<HerdrPane> {
			await bounded(ready.promise, "Herdr dashboard readiness");
			const response = await request("plugin.pane.open", {
				plugin_id: options.pluginId,
				entrypoint: options.pluginEntrypoint,
				placement: "tab",
				cwd: options.vaultRoot,
				focus: true,
				env: {},
			});
			const result = herdrResult(response, "plugin_pane_opened");
			const pluginPane = object(result.plugin_pane);
			const rawPane = pluginPane ? object(pluginPane.pane) : null;
			const paneId = rawPane ? nonEmptyString(rawPane.pane_id) : null;
			if (!paneId)
				throw new Error("Herdr plugin pane response omitted pane_id");
			return waitForPane(paneId);
		},
		async promptAgent(paneId: string): Promise<void> {
			await bounded(ready.promise, "Herdr dashboard readiness");
			herdrResult(
				await request("agent.prompt", {
					target: paneId,
					text: "/collab",
				}),
				"agent_prompted",
			);
		},
		async readPane(paneId: string): Promise<HerdrPaneOutput> {
			await bounded(ready.promise, "Herdr dashboard readiness");
			const result = herdrResult(
				await request("pane.read", {
					pane_id: paneId,
					source: "recent_unwrapped",
					lines: 1000,
					format: "text",
				}),
				"pane_read",
			);
			const read = object(result.read);
			const text = read?.text;
			const revision = read?.revision;
			if (typeof text !== "string" || typeof revision !== "number")
				throw new Error("Herdr pane.read omitted output metadata");
			return { text, revision };
		},
		stop(): void {
			stopped = true;
			connectionEpoch++;
			subscription?.close();
			subscription = undefined;
		},
	};
}
export interface RelayOptions {
	port: number;
	bind: string;
	maxGuestsPerRoom: number;
	maxSockets: number;
	maxFrameBytes: number;
	idleTimeoutSecs: number;
	maxConnectionSecs: number;
	allowedOrigins: readonly string[];
	requireAccessJwt: boolean;
	webRoot: string | null;
	quiet: boolean;
	herdrSocketPath: string;
	vaultRoot: string;
	publicOrigin: string;
	activationTimeoutSecs: number;
	reconnectDelayMs: number;
	scheduleWeekdays: readonly number[];
	scheduleStart: string;
	scheduleStop: string;
	manualOverrideSecs: number;
}

export interface ServiceMetadata {
	status: "available" | "outside-schedule" | "stopping";
	schedule: {
		weekdays: number[];
		start: string;
		stop: string;
		timezone: string;
	};
	manualOverrideUntil: string | null;
}

export interface RelayCallbacks {
	onIdleTimeout?: () => void;
	getServiceMetadata?: () => ServiceMetadata;
	herdrDashboard?: HerdrDashboard;
	onSoftShutdown?: () => void;
}

export const DEFAULT_OPTIONS: RelayOptions = {
	port: 17475,
	bind: "127.0.0.1",
	maxGuestsPerRoom: 1,
	maxSockets: 32,
	maxFrameBytes: PROTOCOL_MAX_FRAME_BYTES,
	idleTimeoutSecs: 1800,
	maxConnectionSecs: 1800,
	allowedOrigins: ["https://omp.midsorbet.me"],
	requireAccessJwt: false,
	webRoot: null,
	quiet: false,
	herdrSocketPath: `${homedir()}/.config/herdr/herdr.sock`,
	vaultRoot: "/Users/me/vault",
	publicOrigin: "https://omp.midsorbet.me",
	activationTimeoutSecs: 30,
	reconnectDelayMs: 250,
	scheduleWeekdays: [1, 2, 3, 4, 5],
	scheduleStart: "08:00",
	scheduleStop: "18:00",
	manualOverrideSecs: 7200,
};

interface SocketData {
	roomId: string;
	role: "host" | "guest";
	peerId: number;
	connectionLifetimeSecs: number;
	expiryTimer?: Timer;
}

type RelaySocket = Bun.ServerWebSocket<SocketData>;

interface Room {
	host: RelaySocket;
	guests: Map<number, RelaySocket>;
	nextPeerId: number;
	openedAtMs: number;
	lastActivityMs: number;
}

export interface CollabRelay {
	url: string;
	port: number;
	stop(): void;
}

function isLoopbackBind(host: string): boolean {
	if (host === "localhost" || host === "::1") return true;
	if (!/^127(?:\.\d{1,3}){3}$/.test(host)) return false;
	return host.split(".").every((octet) => Number(octet) <= 255);
}

function validatePositiveInteger(name: string, value: number): void {
	if (!Number.isInteger(value) || value <= 0)
		throw new Error(`${name} must be a positive integer`);
}

function validateOptions(opts: RelayOptions): void {
	if (!isLoopbackBind(opts.bind))
		throw new Error(`refusing to bind non-loopback address ${opts.bind}`);
	if (!Number.isInteger(opts.port) || opts.port < 0 || opts.port > 65_535)
		throw new Error("port must be between 0 and 65535");
	validatePositiveInteger("maxGuestsPerRoom", opts.maxGuestsPerRoom);
	validatePositiveInteger("maxSockets", opts.maxSockets);
	validatePositiveInteger("maxFrameBytes", opts.maxFrameBytes);
	validatePositiveInteger("idleTimeoutSecs", opts.idleTimeoutSecs);
	validatePositiveInteger("maxConnectionSecs", opts.maxConnectionSecs);
	if (opts.maxFrameBytes > PROTOCOL_MAX_FRAME_BYTES) {
		throw new Error(`maxFrameBytes cannot exceed ${PROTOCOL_MAX_FRAME_BYTES}`);
	}
	for (const origin of opts.allowedOrigins) {
		const parsed = new URL(origin);
		if (parsed.origin !== origin || parsed.protocol !== "https:") {
			throw new Error(`allowed origin must be an https origin: ${origin}`);
		}
	}
	const publicOrigin = new URL(opts.publicOrigin);
	if (
		publicOrigin.protocol !== "https:" ||
		publicOrigin.origin !== opts.publicOrigin
	)
		throw new Error(
			`public origin must be an https origin: ${opts.publicOrigin}`,
		);
	validatePositiveInteger("activationTimeoutSecs", opts.activationTimeoutSecs);
	validatePositiveInteger("reconnectDelayMs", opts.reconnectDelayMs);
	validatePositiveInteger("manualOverrideSecs", opts.manualOverrideSecs);
	if (opts.webRoot !== null) {
		if (
			!isAbsolute(opts.webRoot) ||
			!existsSync(opts.webRoot) ||
			!statSync(opts.webRoot).isDirectory()
		) {
			throw new Error(
				`webRoot must be an existing absolute directory: ${opts.webRoot}`,
			);
		}
	}
}

function accessTokenLifetimeSecs(token: string | null): number | null {
	if (!token) return null;
	const payload = token.split(".", 3)[1];
	if (!payload) return null;
	try {
		const claims: unknown = JSON.parse(
			Buffer.from(payload, "base64url").toString("utf8"),
		);
		if (
			typeof claims !== "object" ||
			claims === null ||
			!("exp" in claims) ||
			typeof claims.exp !== "number" ||
			!Number.isFinite(claims.exp)
		) {
			return null;
		}
		return Math.max(1, Math.floor(claims.exp - Date.now() / 1000));
	} catch {
		return null;
	}
}

interface StaticAsset {
	path: string;
	contentType: string;
	size: number;
	immutable: boolean;
}

const HASHED_ASSET_RE = /^\/[a-z0-9]{8}\.[a-z0-9]+$/;
const STATIC_CONTENT_SECURITY_POLICY = [
	"base-uri 'none'",
	"connect-src 'self'",
	"default-src 'self'",
	"font-src 'self'",
	"form-action 'none'",
	"frame-ancestors 'none'",
	"img-src 'self' data:",
	"manifest-src 'self'",
	"object-src 'none'",
	"script-src 'self'",
	"style-src 'self' 'unsafe-inline'",
].join("; ");

function loadStaticAssets(
	webRoot: string | null,
): ReadonlyMap<string, StaticAsset> {
	const assets = new Map<string, StaticAsset>();
	if (webRoot === null) return assets;
	for (const name of readdirSync(webRoot)) {
		const path = join(webRoot, name);
		const stat = statSync(path);
		if (!stat.isFile()) continue;
		const route = `/${name}`;
		assets.set(route, {
			path,
			contentType: Bun.file(path).type || "application/octet-stream",
			size: stat.size,
			immutable: HASHED_ASSET_RE.test(route),
		});
	}
	const index = assets.get("/index.html");
	if (!index)
		throw new Error(`webRoot does not contain index.html: ${webRoot}`);
	assets.set("/", index);
	return assets;
}

function serveStatic(
	req: Request,
	pathname: string,
	assets: ReadonlyMap<string, StaticAsset>,
): Response | null {
	if (req.method !== "GET" && req.method !== "HEAD") return null;
	const asset = assets.get(pathname);
	if (!asset) return null;
	const headers = new Headers({
		"Cache-Control":
			pathname === "/"
				? "no-store"
				: asset.immutable
					? "public, max-age=31536000, immutable"
					: "public, max-age=300",
		"Content-Length": String(asset.size),
		"Content-Security-Policy": STATIC_CONTENT_SECURITY_POLICY,
		"Content-Type": asset.contentType,
		"Cross-Origin-Opener-Policy": "same-origin",
		"Cross-Origin-Resource-Policy": "same-origin",
		"Permissions-Policy":
			"camera=(), microphone=(), geolocation=(), payment=(), usb=()",
		"Referrer-Policy": "no-referrer",
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options": "DENY",
	});
	return new Response(req.method === "HEAD" ? null : Bun.file(asset.path), {
		headers,
	});
}

export function startRelay(
	overrides: Partial<RelayOptions> = {},
	callbacks: RelayCallbacks = {},
): CollabRelay {
	const opts: RelayOptions = { ...DEFAULT_OPTIONS, ...overrides };
	validateOptions(opts);

	const allowedOrigins = new Set(opts.allowedOrigins);
	const staticAssets = loadStaticAssets(opts.webRoot);
	const rooms = new Map<string, Room>();
	let openSockets = 0;
	let lastRelayActivityMs = Date.now();
	let idleNotified = false;
	let stopped = false;
	let stoppingRequested = false;
	let manualOverrideUntil: number | null = null;
	const log = (message: string): void => {
		if (!opts.quiet) console.log(`[omp-collab-relay] ${message}`);
	};
	const roomTag = (roomId: string): string => `${roomId.slice(0, 8)}…`;

	const noteActivity = (room?: Room): number => {
		const now = Date.now();
		lastRelayActivityMs = now;
		if (room) room.lastActivityMs = now;
		idleNotified = false;
		return now;
	};
	const notifyIdle = (): void => {
		if (idleNotified) return;
		idleNotified = true;
		callbacks.onIdleTimeout?.();
	};

	const closeRoom = (
		roomId: string,
		room: Room,
		hostCode: number,
		hostReason: string,
	): void => {
		rooms.delete(roomId);
		for (const [identity, link] of cachedLinks) {
			if (liveRoomForLink(link) === roomId) cachedLinks.delete(identity);
		}
		const closure = JSON.stringify({
			t: "room-closed",
		} satisfies RelayControlToGuest);
		for (const guest of room.guests.values()) {
			guest.send(closure);
			guest.close(4001, "room closed");
		}
		room.guests.clear();
		room.host.close(hostCode, hostReason);
		if (stoppingRequested && rooms.size === 0) callbacks.onSoftShutdown?.();
	};
	const dashboard =
		callbacks.herdrDashboard ??
		createHerdrDashboard({
			socketPath: opts.herdrSocketPath,
			vaultRoot: opts.vaultRoot,
			activationTimeoutMs: opts.activationTimeoutSecs * 1000,
			reconnectDelayMs: opts.reconnectDelayMs,
			pluginId: "local.omp-dashboard",
			pluginEntrypoint: "agent",
		});
	const cachedLinks = new Map<string, string>();
	const activationPromises = new Map<string, Promise<string>>();
	const decodedPaneId = (pathname: string): string | null => {
		const encoded = pathname.slice("/api/agents/".length).split("/")[0] ?? "";
		try {
			const paneId = decodeURIComponent(encoded);
			return /^w[A-Za-z0-9_-]+:p[A-Za-z0-9_-]+$/.test(paneId) ? paneId : null;
		} catch {
			return null;
		}
	};
	const canonicalLink = (link: string): string | null => {
		try {
			const outer = new URL(link);
			const publicUrl = new URL(opts.publicOrigin);
			const localWebOrigin = `http://127.0.0.1:${server.port}`;
			if (
				(outer.origin !== publicUrl.origin &&
					outer.origin !== localWebOrigin) ||
				!outer.hash
			)
				return null;
			const inner = new URL(outer.hash.slice(1));
			const localRelay = `${opts.bind}:${server.port}`;
			const isLocal =
				inner.protocol === "ws:" &&
				(inner.host === localRelay ||
					inner.host === `127.0.0.1:${server.port}`);
			const isPublic =
				inner.protocol === "wss:" && inner.host === publicUrl.host;
			if (!isLocal && !isPublic) return null;
			const match = ROOM_LINK_PATH_RE.exec(inner.pathname);
			if (!match || Buffer.from(match[2]!, "base64url").byteLength !== 48)
				return null;
			return `${publicUrl.origin}/#wss://${publicUrl.host}${inner.pathname}`;
		} catch {
			return null;
		}
	};
	const liveRoomForLink = (link: string): string | null => {
		const canonical = canonicalLink(link);
		if (!canonical) return null;
		try {
			const inner = new URL(new URL(canonical).hash.slice(1));
			const match = ROOM_LINK_PATH_RE.exec(inner.pathname);
			return match && rooms.has(match[1]!) ? match[1]! : null;
		} catch {
			return null;
		}
	};
	const listAgents = async (): Promise<DashboardAgent[]> => {
		await dashboard.refresh();
		const panes = await dashboard.listPanes();
		const liveIdentities = new Set(panes.map((pane) => pane.identity));
		for (const [identity, link] of cachedLinks) {
			if (!liveIdentities.has(identity) || !liveRoomForLink(link))
				cachedLinks.delete(identity);
		}
		return panes.map((pane) => ({
			id: pane.id,
			label: pane.label,
			cwd: pane.cwd,
			status: pane.status,
			focused: pane.focused,
			remoteCached: cachedLinks.has(pane.identity),
		}));
	};
	const activateAgent = async (paneId: string): Promise<string> => {
		if (stoppingRequested) throw new Error("service is stopping");
		const pane = (await dashboard.listPanes()).find(
			(candidate) => candidate.id === paneId,
		);
		if (!pane) throw new Error("agent pane not found");
		const cached = cachedLinks.get(pane.identity);
		if (cached && liveRoomForLink(cached)) return cached;
		cachedLinks.delete(pane.identity);
		const existing = activationPromises.get(pane.identity);
		if (existing) return existing;
		const activation = (async (): Promise<string> => {
			await dashboard.readPane(paneId);
			await dashboard.promptAgent(paneId);
			const deadline = Date.now() + opts.activationTimeoutSecs * 1000;
			let canonical: string | null = null;
			for (;;) {
				const output = await dashboard.readPane(paneId);
				const candidates = renderedCollabLinkCandidates(output.text);
				for (const candidate of candidates.reverse()) {
					const link = /^[a-z]+:\/\//i.test(candidate)
						? candidate
						: `${candidate.startsWith("127.") || candidate.startsWith("localhost") ? "http" : "https"}://${candidate}`;
					canonical = canonicalLink(link);
					if (canonical && liveRoomForLink(canonical)) break;
					canonical = null;
				}
				if (canonical) break;
				if (Date.now() >= deadline)
					throw new Error("agent activation timed out");
				await Bun.sleep(100);
			}
			await dashboard.refresh();
			const current = (await dashboard.listPanes()).find(
				(candidate) => candidate.identity === pane.identity,
			);
			if (!current || current.identity !== pane.identity)
				throw new Error("agent pane session disappeared");
			cachedLinks.set(pane.identity, canonical!);
			return canonical!;
		})();
		activationPromises.set(pane.identity, activation);
		try {
			return await activation;
		} finally {
			activationPromises.delete(pane.identity);
		}
	};
	let overrideTimer: Timer | undefined;
	const withinSchedule = (now = new Date()): boolean => {
		const [startHour, startMinute] = opts.scheduleStart.split(":").map(Number);
		const [stopHour, stopMinute] = opts.scheduleStop.split(":").map(Number);
		const minutes = now.getHours() * 60 + now.getMinutes();
		return (
			opts.scheduleWeekdays.includes(now.getDay()) &&
			minutes >= startHour! * 60 + startMinute! &&
			minutes < stopHour! * 60 + stopMinute!
		);
	};
	const serviceMetadata = (): ServiceMetadata => {
		const callbackMetadata = callbacks.getServiceMetadata?.();
		if (callbackMetadata)
			return stoppingRequested
				? { ...callbackMetadata, status: "stopping" }
				: callbackMetadata;
		const scheduled = withinSchedule();
		return {
			status: stoppingRequested
				? "stopping"
				: scheduled || (manualOverrideUntil ?? 0) > Date.now()
					? "available"
					: "outside-schedule",
			schedule: {
				weekdays: [...opts.scheduleWeekdays],
				start: opts.scheduleStart,
				stop: opts.scheduleStop,
				timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
			},
			manualOverrideUntil: manualOverrideUntil
				? new Date(manualOverrideUntil).toISOString()
				: null,
		};
	};
	const jsonError = (error: unknown): Response =>
		Response.json(
			{ error: error instanceof Error ? error.message : "request failed" },
			{ status: 400, headers: { "Cache-Control": "no-store" } },
		);

	const scheduleExpiry = (ws: RelaySocket): void => {
		const lifetimeSecs = ws.data.connectionLifetimeSecs;
		ws.data.expiryTimer = setTimeout(() => {
			log(
				`${ws.data.role} connection for room ${roomTag(ws.data.roomId)} reached its ${lifetimeSecs}s lifetime`,
			);
			ws.close(4001, "Cloudflare Access session expired");
		}, lifetimeSecs * 1000);
	};

	const server = Bun.serve<SocketData>({
		hostname: opts.bind,
		port: opts.port,
		idleTimeout: Math.max(10, Math.ceil(opts.activationTimeoutSecs + 5)),
		maxRequestBodySize: 8192,
		async fetch(req, srv): Promise<Response | undefined> {
			const url = new URL(req.url);
			if (req.method === "GET" && url.pathname === "/healthz")
				return new Response("omp-collab-relay\n");

			const match =
				req.method === "GET" ? ROOM_PATH_RE.exec(url.pathname) : null;
			const role = url.searchParams.get("role");
			const origin = req.headers.get("origin");
			const forwarded =
				req.headers.has("cf-ray") ||
				req.headers.has("cf-connecting-ip") ||
				req.headers.has("x-forwarded-for");
			const localHostSocket =
				match !== null && role === "host" && origin === null && !forwarded;
			const isApi =
				url.pathname === "/api/agents" ||
				url.pathname.startsWith("/api/agents/") ||
				url.pathname.startsWith("/api/service");
			const mutatingApi =
				isApi && req.method !== "GET" && req.method !== "HEAD";
			const localServiceControl =
				req.method === "POST" &&
				(url.pathname === "/api/service/override" ||
					url.pathname === "/api/service/stop") &&
				origin === null &&
				!forwarded;
			const accessJwt = req.headers.get("cf-access-jwt-assertion");
			if (
				opts.requireAccessJwt &&
				!accessJwt &&
				!localHostSocket &&
				!localServiceControl
			) {
				return new Response("unauthorized", {
					status: 401,
					headers: { "Cache-Control": "no-store" },
				});
			}
			if (
				mutatingApi &&
				!localServiceControl &&
				(origin === null || !allowedOrigins.has(origin))
			)
				return new Response("forbidden", {
					status: 403,
					headers: { "Cache-Control": "no-store" },
				});
			if (localServiceControl && url.pathname === "/api/service/override") {
				manualOverrideUntil = Date.now() + opts.manualOverrideSecs * 1000;
				clearTimeout(overrideTimer);
				overrideTimer = setTimeout(() => {
					manualOverrideUntil = null;
					if (withinSchedule()) return;
					stoppingRequested = true;
					if (rooms.size === 0) callbacks.onSoftShutdown?.();
				}, opts.manualOverrideSecs * 1000);
				return Response.json(serviceMetadata(), {
					headers: { "Cache-Control": "no-store" },
				});
			}
			if (localServiceControl && url.pathname === "/api/service/stop") {
				stoppingRequested = true;
				if (rooms.size === 0) callbacks.onSoftShutdown?.();
				return Response.json(serviceMetadata(), {
					headers: { "Cache-Control": "no-store" },
				});
			}
			if (req.method === "GET" && url.pathname === "/api/agents") {
				try {
					return Response.json(await listAgents(), {
						headers: { "Cache-Control": "no-store" },
					});
				} catch (error) {
					return jsonError(error);
				}
			}
			if (req.method === "POST" && url.pathname === "/api/agents") {
				try {
					const pane = await dashboard.createAgent();
					return Response.json(
						{
							id: pane.id,
							label: pane.label,
							cwd: pane.cwd,
							status: pane.status,
							focused: pane.focused,
							remoteCached: false,
						} satisfies DashboardAgent,
						{ status: 201, headers: { "Cache-Control": "no-store" } },
					);
				} catch (error) {
					return jsonError(error);
				}
			}
			if (
				req.method === "POST" &&
				url.pathname.startsWith("/api/agents/") &&
				url.pathname.endsWith("/activate")
			) {
				const paneId = decodedPaneId(url.pathname);
				if (!paneId) return new Response("not found", { status: 404 });
				try {
					const link = await activateAgent(paneId);
					return Response.json(
						{ link },
						{ headers: { "Cache-Control": "no-store" } },
					);
				} catch (error) {
					return jsonError(error);
				}
			}
			if (req.method === "GET" && url.pathname === "/api/service")
				return Response.json(serviceMetadata(), {
					headers: { "Cache-Control": "no-store" },
				});
			if (req.method === "GET" && url.pathname.startsWith("/open/"))
				return new Response(LOADING_HTML, {
					headers: {
						"Cache-Control": "no-store",
						"Content-Type": "text/html; charset=utf-8",
					},
				});

			const assetResponse = serveStatic(req, url.pathname, staticAssets);
			if (assetResponse) return assetResponse;
			if (!match || (role !== "host" && role !== "guest"))
				return new Response("not found", { status: 404 });
			if (origin !== null && !allowedOrigins.has(origin))
				return new Response("forbidden", { status: 403 });

			const connectionLifetimeSecs = Math.min(
				opts.maxConnectionSecs,
				accessTokenLifetimeSecs(accessJwt) ?? opts.maxConnectionSecs,
			);
			const data: SocketData = {
				roomId: match[1]!,
				role,
				peerId: 0,
				connectionLifetimeSecs,
			};
			if (srv.upgrade(req, { data })) return undefined;
			return new Response("websocket upgrade required", { status: 426 });
		},
		websocket: {
			maxPayloadLength: PROTOCOL_MAX_FRAME_BYTES,
			open(ws: RelaySocket): void {
				openSockets++;
				const { roomId, role } = ws.data;
				if (openSockets > opts.maxSockets) {
					log(`rejected ${role}: socket limit ${opts.maxSockets} reached`);
					ws.close(4029, "relay is at its socket limit");
					return;
				}
				if (role === "host") {
					if (stoppingRequested) {
						ws.close(4001, "service is stopping");
						return;
					}
					if (rooms.has(roomId)) {
						ws.close(4009, "a host is already connected for this room");
						return;
					}
					const now = noteActivity();
					rooms.set(roomId, {
						host: ws,
						guests: new Map(),
						nextPeerId: 1,
						openedAtMs: now,
						lastActivityMs: now,
					});
					scheduleExpiry(ws);
					log(
						`host connected, room ${roomTag(roomId)} open (rooms=${rooms.size}, sockets=${openSockets})`,
					);
					return;
				}
				const room = rooms.get(roomId);
				if (!room) {
					ws.close(4004, "no such room");
					return;
				}
				if (room.guests.size >= opts.maxGuestsPerRoom) {
					log(`rejected guest: room ${roomTag(roomId)} is full`);
					ws.close(4030, "room is full, try again later");
					return;
				}
				const peerId = room.nextPeerId++;
				ws.data.peerId = peerId;
				room.guests.set(peerId, ws);
				scheduleExpiry(ws);
				noteActivity(room);
				room.host.send(
					JSON.stringify({
						t: "peer-joined",
						peer: peerId,
					} satisfies RelayControlToHost),
				);
				log(
					`guest ${peerId} joined room ${roomTag(roomId)} (guests=${room.guests.size}, sockets=${openSockets})`,
				);
			},
			message(ws: RelaySocket, message: string | Buffer): void {
				if (
					typeof message === "string" ||
					message.byteLength < ENVELOPE_HEADER_LENGTH
				)
					return;
				const room = rooms.get(ws.data.roomId);
				if (!room) return;
				if (message.byteLength > opts.maxFrameBytes) {
					if (ws.data.role === "host" && room.host === ws) {
						log(
							`host frame of ${message.byteLength}B exceeds cap ${opts.maxFrameBytes}B, closing room ${roomTag(ws.data.roomId)}`,
						);
						closeRoom(ws.data.roomId, room, 4001, "frame too large");
					} else {
						log(
							`closing ${ws.data.role} socket: frame of ${message.byteLength}B exceeds cap ${opts.maxFrameBytes}B`,
						);
						ws.close(4013, "frame too large");
					}
					return;
				}
				if (ws.data.role === "host") {
					if (room.host !== ws) return;
					noteActivity(room);
					const peerId = message.readUInt32BE(0);
					if (peerId === 0) {
						for (const guest of room.guests.values()) guest.send(message);
					} else {
						room.guests.get(peerId)?.send(message);
					}
					return;
				}
				if (room.guests.get(ws.data.peerId) !== ws) return;
				noteActivity(room);
				message.writeUInt32BE(ws.data.peerId, 0);
				room.host.send(message);
			},
			close(ws: RelaySocket): void {
				clearTimeout(ws.data.expiryTimer);
				openSockets = Math.max(0, openSockets - 1);
				const { roomId, role, peerId } = ws.data;
				const room = rooms.get(roomId);
				if (!room) return;
				if (role === "host") {
					if (room.host !== ws) return;
					noteActivity();
					rooms.delete(roomId);
					if (stoppingRequested && rooms.size === 0)
						callbacks.onSoftShutdown?.();
					const closure = JSON.stringify({
						t: "room-closed",
					} satisfies RelayControlToGuest);
					for (const guest of room.guests.values()) {
						guest.send(closure);
						guest.close(4001, "room closed");
					}
					room.guests.clear();
					log(
						`host left, room ${roomTag(roomId)} closed (rooms=${rooms.size}, sockets=${openSockets})`,
					);
					return;
				}
				if (room.guests.delete(peerId)) {
					noteActivity(room);
					room.host.send(
						JSON.stringify({
							t: "peer-left",
							peer: peerId,
						} satisfies RelayControlToHost),
					);
					log(
						`guest ${peerId} left room ${roomTag(roomId)} (guests=${room.guests.size}, sockets=${openSockets})`,
					);
				}
			},
		},
	});

	const sweepMs = Math.min(
		Math.max(Math.floor(opts.idleTimeoutSecs * 250), 250),
		30_000,
	);
	const sweeper = setInterval(() => {
		const now = Date.now();
		const cutoff = now - opts.idleTimeoutSecs * 1000;
		let closedIdleRoom = false;
		for (const [roomId, room] of rooms) {
			if (room.lastActivityMs > cutoff) continue;
			log(`room ${roomTag(roomId)} idle for ${opts.idleTimeoutSecs}s, closing`);
			closeRoom(roomId, room, 4001, "room closed");
			closedIdleRoom = true;
		}
		if (
			rooms.size === 0 &&
			(closedIdleRoom ||
				now - lastRelayActivityMs > opts.idleTimeoutSecs * 1000)
		)
			notifyIdle();
	}, sweepMs);

	const displayHost = opts.bind.includes(":") ? `[${opts.bind}]` : opts.bind;
	log(
		`listening on http://${displayHost}:${server.port} ` +
			`(guests/room<=${opts.maxGuestsPerRoom}, sockets<=${opts.maxSockets}, ` +
			`frame<=${opts.maxFrameBytes}B, idle=${opts.idleTimeoutSecs}s, connection<=${opts.maxConnectionSecs}s, ` +
			`access-jwt=${opts.requireAccessJwt ? "required" : "optional"})`,
	);

	return {
		url: `ws://${displayHost}:${server.port}`,
		port: server.port,
		stop(): void {
			if (stopped) return;
			stopped = true;
			clearInterval(sweeper);
			dashboard.stop();
			for (const [roomId, room] of rooms)
				closeRoom(roomId, room, 4001, "relay shutting down");
			server.stop(true);
		},
	};
}

function usage(): string {
	return `usage: omp-collab-relay [options]

Options:
  --port <n>                    Loopback port (default: ${DEFAULT_OPTIONS.port})
  --bind <address>              Loopback bind address (default: ${DEFAULT_OPTIONS.bind})
  --max-guests-per-room <n>     Guest cap per room (default: ${DEFAULT_OPTIONS.maxGuestsPerRoom})
  --max-sockets <n>             Total socket cap (default: ${DEFAULT_OPTIONS.maxSockets})
  --max-frame-bytes <n>         Frame cap, at most ${PROTOCOL_MAX_FRAME_BYTES}
  --idle-timeout-secs <n>       Shut down after room/relay inactivity (default: ${DEFAULT_OPTIONS.idleTimeoutSecs})
  --max-connection-secs <n>     Hard WebSocket lifetime (default: ${DEFAULT_OPTIONS.maxConnectionSecs})
  --allowed-origin <https-url>  Browser Origin to allow; repeatable (default: ${DEFAULT_OPTIONS.allowedOrigins.join(", ")})
  --require-access-jwt          Require a Cloudflare Access JWT except for the local native host
  --web-root <absolute-path>    Serve the browser guest client from this directory
  --herdr-socket-path <path>   Herdr v0.8 local socket (default: ${DEFAULT_OPTIONS.herdrSocketPath})
  --vault-root <absolute-path> New agent working directory (default: ${DEFAULT_OPTIONS.vaultRoot})
  --public-origin <https-url>  Dashboard public origin (default: ${DEFAULT_OPTIONS.publicOrigin})
  --activation-timeout-secs <n> Herdr activation deadline (default: ${DEFAULT_OPTIONS.activationTimeoutSecs})
  --reconnect-delay-ms <n>     Herdr reconnect delay (default: ${DEFAULT_OPTIONS.reconnectDelayMs})
  --schedule-weekdays <list>    Local weekdays, e.g. 1,2,3,4,5
  --schedule-start <HH:MM>      Local schedule start (default: ${DEFAULT_OPTIONS.scheduleStart})
  --schedule-stop <HH:MM>       Local schedule stop (default: ${DEFAULT_OPTIONS.scheduleStop})
  --manual-override-secs <n>    Manual availability override (default: ${DEFAULT_OPTIONS.manualOverrideSecs})
  --quiet                       Suppress relay logs
  --help                        Show this help`;
}

function parseInteger(flag: string, raw: string | undefined): number {
	const value = Number(raw);
	if (!Number.isInteger(value)) throw new Error(`${flag} requires an integer`);
	return value;
}

function parseArgs(argv: readonly string[]): Partial<RelayOptions> {
	const parsed: Partial<RelayOptions> = {};
	const origins: string[] = [];
	for (let i = 0; i < argv.length; i++) {
		const flag = argv[i]!;
		const next = (): string => {
			const value = argv[++i];
			if (value === undefined) throw new Error(`${flag} requires a value`);
			return value;
		};
		switch (flag) {
			case "--port":
				parsed.port = parseInteger(flag, next());
				break;
			case "--bind":
				parsed.bind = next();
				break;
			case "--max-guests-per-room":
				parsed.maxGuestsPerRoom = parseInteger(flag, next());
				break;
			case "--max-sockets":
				parsed.maxSockets = parseInteger(flag, next());
				break;
			case "--max-frame-bytes":
				parsed.maxFrameBytes = parseInteger(flag, next());
				break;
			case "--idle-timeout-secs":
				parsed.idleTimeoutSecs = parseInteger(flag, next());
				break;
			case "--max-connection-secs":
				parsed.maxConnectionSecs = parseInteger(flag, next());
				break;
			case "--allowed-origin":
				origins.push(next());
				break;
			case "--web-root":
				parsed.webRoot = next();
				break;
			case "--herdr-socket-path":
				parsed.herdrSocketPath = next();
				break;
			case "--vault-root":
				parsed.vaultRoot = next();
				break;
			case "--public-origin":
				parsed.publicOrigin = next();
				break;
			case "--activation-timeout-secs":
				parsed.activationTimeoutSecs = parseInteger(flag, next());
				break;
			case "--reconnect-delay-ms":
				parsed.reconnectDelayMs = parseInteger(flag, next());
				break;
			case "--schedule-weekdays":
				parsed.scheduleWeekdays = next()
					.split(",")
					.map((value) => parseInteger(flag, value));
				break;
			case "--schedule-start":
				parsed.scheduleStart = next();
				break;
			case "--schedule-stop":
				parsed.scheduleStop = next();
				break;
			case "--manual-override-secs":
				parsed.manualOverrideSecs = parseInteger(flag, next());
				break;
			case "--require-access-jwt":
				parsed.requireAccessJwt = true;
				break;
			case "--quiet":
				parsed.quiet = true;
				break;
			case "--help":
				console.log(usage());
				process.exit(0);
			default:
				throw new Error(`unknown option: ${flag}`);
		}
	}
	if (origins.length > 0) parsed.allowedOrigins = origins;
	return parsed;
}

if (import.meta.main) {
	let relay: CollabRelay | undefined;
	let stopping = false;
	const shutdown = (code: number): void => {
		if (stopping) return;
		stopping = true;
		relay?.stop();
		process.exit(code);
	};
	try {
		const options = parseArgs(Bun.argv.slice(2));
		relay = startRelay(options, {
			onSoftShutdown: () => shutdown(0),
		});
	} catch (error) {
		console.error(
			`omp-collab-relay: ${error instanceof Error ? error.message : String(error)}`,
		);
		console.error(usage());
		process.exit(2);
	}
	process.on("SIGINT", () => shutdown(0));
	process.on("SIGTERM", () => shutdown(0));
}
