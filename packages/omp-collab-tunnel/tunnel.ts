/**
 * omp-collab-tunnel — on-demand OMP collab sharing through a Cloudflare
 * Quick Tunnel, as one compiled binary.
 *
 * Runs the hardened loopback relay (`./relay.ts`) in-process, spawns the
 * Nix-provided `cloudflared` (path via $OMP_COLLAB_CLOUDFLARED, set by the
 * package wrapper; falls back to PATH for dev runs), and prints the
 * `/collab wss://…` command once the public endpoint is usable.
 *
 * Tunnel discovery: primary source is cloudflared's local metrics server —
 * `GET /quicktunnel` returns the assigned hostname and `GET /ready` reports
 * edge connectivity (verified against cloudflared 2026.6.1). Those endpoints
 * are not formally documented, so a stdout/stderr URL scan is kept as a
 * fallback for hostname discovery. The public hostname is never queried
 * through DNS before the tunnel is up: fresh trycloudflare.com names can
 * take minutes to publish, and early queries prime local negative caches
 * (e.g. WARP/Gateway resolvers).
 *
 * Shutdown: SIGINT/SIGTERM terminate cloudflared (SIGTERM, then SIGKILL
 * after 5s) and stop the relay before exiting; an unexpected cloudflared or
 * relay death exits nonzero. cloudflared output is only shown on failure,
 * with `/r/<roomId>` paths redacted.
 */

import net from "node:net";
import { type CollabRelay, DEFAULT_OPTIONS, type RelayOptions, startRelay } from "./relay";
import { clearTunnelState, writeTunnelState } from "./state";

const CLOUDFLARED_BIN = process.env.OMP_COLLAB_CLOUDFLARED ?? "cloudflared";
const TUNNEL_HOST_RE = /https:\/\/([a-zA-Z0-9-]+)\.trycloudflare\.com/;
const ROOM_PATH_REDACT_RE = /\/r\/[A-Za-z0-9_-]+[^\s"]*/g;
const LOG_TAIL_LINES = 40;

// ═══════════════════════════════════════════════════════════════════════════
// CLI
// ═══════════════════════════════════════════════════════════════════════════

const NUMERIC_FLAGS: Record<string, "port" | "maxRooms" | "maxGuestsPerRoom" | "maxSockets" | "maxFrameBytes" | "idleTimeoutSecs"> = {
	"--port": "port",
	"--max-rooms": "maxRooms",
	"--max-guests": "maxGuestsPerRoom",
	"--max-sockets": "maxSockets",
	"--max-frame-bytes": "maxFrameBytes",
	"--idle-timeout-secs": "idleTimeoutSecs",
};

function usage(): string {
	return `usage: omp-collab-tunnel [options]

Starts a hardened loopback-only OMP collab relay plus a temporary Cloudflare
Quick Tunnel, then publishes that tunnel as the default relay for new OMP
sessions while this command runs. Stop with Ctrl-C to tear everything down.

options:
  --relay-only           run only the loopback relay, no public tunnel
  --port N               relay listen port (default ${DEFAULT_OPTIONS.port})
  --bind ADDR            loopback listen address (default ${DEFAULT_OPTIONS.bind})
  --max-rooms N          concurrent room limit (default ${DEFAULT_OPTIONS.maxRooms})
  --max-guests N         guests per room (default ${DEFAULT_OPTIONS.maxGuestsPerRoom})
  --max-sockets N        total websocket limit (default ${DEFAULT_OPTIONS.maxSockets})
  --max-frame-bytes N    websocket frame cap (default ${DEFAULT_OPTIONS.maxFrameBytes})
  --idle-timeout-secs N  idle room teardown (default ${DEFAULT_OPTIONS.idleTimeoutSecs})
  -h, --help             show this help

notes:
  - New OMP sessions started while this command runs can use bare "/collab";
    the wrapper injects the generated relay URL through an ephemeral config
    overlay. Existing OMP sessions do not reload config; use the printed
    "/collab wss://..." command there.
  - The printed wss://...trycloudflare.com URL is public internet attack
    surface while this command runs. Share the collab link only with the
    intended guest; prefer "/collab view" for lower-trust observers.
  - Terminal-only v1: browser click-to-join and QR links are NOT supported
    (GET / serves no client), and /share self-hosting is disabled. Guests
    join from a terminal, e.g. omp join "<link>".
  - The relay is content-blind, but OMP's collab wire protocol (v3 as of
    16.3.x) is checked between host and guest: run matching OMP versions on
    both ends or the guest is rejected during handshake.
  - Quiet sessions are torn down by the relay after the idle timeout
    (connection liveness does not count); raise --idle-timeout-secs for
    long passive sessions.`;
}

function fail(message: string): never {
	console.error(`omp-collab-tunnel: ${message}`);
	console.error(usage());
	process.exit(2);
}

interface TunnelCli {
	overrides: Partial<RelayOptions>;
	relayOnly: boolean;
}

function parseArgs(argv: readonly string[]): TunnelCli {
	const overrides: Partial<RelayOptions> = {};
	let relayOnly = false;
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i]!;
		if (arg === "-h" || arg === "--help") {
			console.log(usage());
			process.exit(0);
		}
		if (arg === "--relay-only") {
			relayOnly = true;
			continue;
		}
		const eq = arg.indexOf("=");
		const flag = eq === -1 ? arg : arg.slice(0, eq);
		const rawValue = eq === -1 ? argv[++i] : arg.slice(eq + 1);
		if (flag === "--bind") {
			if (rawValue === undefined) fail("missing value for --bind");
			overrides.bind = rawValue;
			continue;
		}
		const key = NUMERIC_FLAGS[flag];
		if (!key) fail(`unknown argument ${arg}`);
		const value = Number(rawValue);
		if (rawValue === undefined || rawValue === "" || !Number.isInteger(value) || value < 0) {
			fail(`invalid value for ${flag}: ${rawValue === undefined ? "<missing>" : rawValue}`);
		}
		if (key === "port") {
			if (value > 65_535) fail(`invalid value for --port: ${rawValue}`);
		} else if (value < 1) {
			fail(`invalid value for ${flag}: ${rawValue} (must be >= 1)`);
		}
		overrides[key] = value;
	}
	return { overrides, relayOnly };
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

function freeLoopbackPort(): Promise<number> {
	const { promise, resolve, reject } = Promise.withResolvers<number>();
	const srv = net.createServer();
	srv.once("error", reject);
	srv.listen(0, "127.0.0.1", () => {
		const address = srv.address() as net.AddressInfo;
		srv.close(() => resolve(address.port));
	});
	return promise;
}

async function fetchOk(url: string, timeoutMs = 2_000): Promise<Response | null> {
	try {
		const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
		return res.ok ? res : null;
	} catch {
		return null;
	}
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

const { overrides, relayOnly } = parseArgs(Bun.argv.slice(2));

let relay: CollabRelay;
try {
	relay = startRelay(overrides);
} catch (err) {
	const message = err instanceof Error ? err.message : String(err);
	console.error(`omp-collab-tunnel: relay startup failed: ${message}`);
	if (/in use|EADDRINUSE/i.test(message)) {
		console.error("omp-collab-tunnel: pick another port with --port");
	}
	process.exit(1);
}

let cloudflared: Bun.Subprocess<"ignore", "pipe", "pipe"> | null = null;
let shuttingDown = false;

const logTail: string[] = [];
let scannedHost: string | null = null;

function dumpTunnelLog(): void {
	// cloudflared's log format is outside this repo's control; redact anything
	// that looks like a room path (connect-as-guest capability) before showing.
	for (const line of logTail) {
		console.error(line.replace(ROOM_PATH_REDACT_RE, "/r/<redacted>"));
	}
}

async function shutdown(code: number): Promise<never> {
	if (shuttingDown) process.exit(code);
	shuttingDown = true;
	await clearTunnelState();
	if (cloudflared && cloudflared.exitCode === null) {
		cloudflared.kill();
		const exited = await Promise.race([cloudflared.exited, Bun.sleep(5_000).then(() => null)]);
		if (exited === null) {
			cloudflared.kill(9);
			await cloudflared.exited;
		}
	}
	relay.stop();
	process.exit(code);
}

process.on("SIGINT", () => void shutdown(130));
process.on("SIGTERM", () => void shutdown(143));

if (!relayOnly) {
	const bind = overrides.bind ?? DEFAULT_OPTIONS.bind;
	const originHost = bind.includes(":") ? `[${bind}]` : bind;

	// Some quick tunnels intermittently never become publicly reachable even
	// though cloudflared reports the edge connection up and the hostname is
	// published in DNS (observed 2026-07-03: good tunnels answer /healthz
	// within ~30s; bad ones stay dead for 6+ minutes). Recycling gets a fresh
	// hostname, so treat reachability as a per-attempt gate and retry.
	const MAX_ATTEMPTS = 3;
	const EDGE_TIMEOUT_MS = 60_000;
	const PUBLIC_TIMEOUT_MS = 90_000;

	/**
	 * One quick-tunnel attempt: spawn cloudflared, discover the hostname and
	 * edge readiness via the local metrics server (log scan as hostname
	 * fallback), then require a public /healthz success. On failure the child
	 * is terminated and null is returned. The public hostname is never
	 * queried through DNS before the tunnel is up at the edge: fresh
	 * trycloudflare.com names can take a while to publish, and early queries
	 * prime local negative caches (e.g. WARP/Gateway resolvers).
	 */
	const attemptTunnel = async (): Promise<string | null> => {
		logTail.length = 0;
		scannedHost = null;
		const metricsPort = await freeLoopbackPort();
		const proc = Bun.spawn(
			[CLOUDFLARED_BIN, "tunnel", "--no-autoupdate", "--url", `http://${originHost}:${relay.port}`, "--metrics", `127.0.0.1:${metricsPort}`],
			{ stdin: "ignore", stdout: "pipe", stderr: "pipe" },
		);
		cloudflared = proc; // visible to shutdown() for Ctrl-C during startup

		const scanStream = async (stream: ReadableStream<Uint8Array>): Promise<void> => {
			const decoder = new TextDecoder();
			let buffer = "";
			for await (const chunk of stream) {
				buffer += decoder.decode(chunk, { stream: true });
				let newline = buffer.indexOf("\n");
				while (newline !== -1) {
					const line = buffer.slice(0, newline);
					buffer = buffer.slice(newline + 1);
					logTail.push(line);
					if (logTail.length > LOG_TAIL_LINES) logTail.shift();
					if (!scannedHost) {
						const match = TUNNEL_HOST_RE.exec(line);
						if (match && match[1] !== "api") scannedHost = `${match[1]}.trycloudflare.com`;
					}
					newline = buffer.indexOf("\n");
				}
			}
		};
		void scanStream(proc.stdout);
		void scanStream(proc.stderr);

		const failAttempt = async (reason: string): Promise<null> => {
			console.error(`attempt failed: ${reason}`);
			dumpTunnelLog();
			if (proc.exitCode === null) {
				proc.kill();
				const exited = await Promise.race([proc.exited, Bun.sleep(5_000).then(() => null)]);
				if (exited === null) {
					proc.kill(9);
					await proc.exited;
				}
			}
			return null;
		};

		console.log("waiting for the tunnel to come up at the Cloudflare edge...");
		let hostname: string | null = null;
		let edgeReady = false;
		const edgeDeadline = Date.now() + EDGE_TIMEOUT_MS;
		while (Date.now() < edgeDeadline && !(hostname && edgeReady)) {
			if (proc.exitCode !== null) return failAttempt(`cloudflared exited during startup (code ${proc.exitCode})`);
			if (!hostname) {
				const quick = await fetchOk(`http://127.0.0.1:${metricsPort}/quicktunnel`);
				let parsed: { hostname?: string } | null = null;
				if (quick) {
					try {
						parsed = (await quick.json()) as { hostname?: string };
					} catch {
						// Undocumented endpoint: tolerate a non-JSON body and let
						// the log-scan fallback supply the hostname instead.
					}
				}
				hostname = parsed?.hostname || scannedHost;
				if (hostname) console.log(`tunnel hostname assigned: ${hostname} (not public yet)`);
			}
			if (!edgeReady) {
				edgeReady = (await fetchOk(`http://127.0.0.1:${metricsPort}/ready`)) !== null;
			}
			if (hostname && edgeReady) break;
			await Bun.sleep(1_000);
		}
		if (!hostname) return failAttempt("no trycloudflare.com hostname appeared (metrics or logs)");
		if (!edgeReady) console.log("note: edge readiness was not confirmed via metrics; continuing to the public check...");

		// Hard gate: the banner must only print once the public URL actually
		// works — the same condition guests need.
		console.log(`waiting for https://${hostname} to become publicly reachable...`);
		const publicDeadline = Date.now() + PUBLIC_TIMEOUT_MS;
		let waited = 0;
		while (Date.now() < publicDeadline) {
			if (proc.exitCode !== null) return failAttempt(`cloudflared exited (code ${proc.exitCode})`);
			if ((await fetchOk(`https://${hostname}/healthz`, 5_000)) !== null) return hostname;
			waited += 5;
			if (waited % 30 === 0) console.log(`still waiting for public reachability (${waited}s)...`);
			await Bun.sleep(5_000);
		}
		return failAttempt(`https://${hostname}/healthz not reachable within ${PUBLIC_TIMEOUT_MS / 1000}s`);
	};

	let hostname: string | null = null;
	for (let attempt = 1; attempt <= MAX_ATTEMPTS && !hostname && !shuttingDown; attempt++) {
		if (attempt > 1) console.log(`recycling the quick tunnel for a fresh hostname (attempt ${attempt}/${MAX_ATTEMPTS})...`);
		hostname = await attemptTunnel();
	}
	if (!hostname) {
		console.error(`error: no publicly reachable quick tunnel after ${MAX_ATTEMPTS} attempts`);
		relay.stop();
		process.exit(1);
	}

	// Only after success: an unexpected cloudflared death now ends the session.
	const proc = cloudflared!;
	void proc.exited.then(async code => {
		if (shuttingDown) return;
		console.error(`error: cloudflared exited unexpectedly (code ${code})`);
		dumpTunnelLog();
		await clearTunnelState();
		relay.stop();
		process.exit(1);
	});

	const relayUrl = `wss://${hostname}`;
	let statePath: string;
	try {
		statePath = (await writeTunnelState(relayUrl)).config;
	} catch (err) {
		console.error(`error: failed to publish OMP collab default config: ${err instanceof Error ? err.message : String(err)}`);
		await shutdown(1);
	}
	console.log(`
OMP collab quick tunnel is live.

  Local relay:  http://${originHost}:${relay.port}  (loopback only)
  Public relay: ${relayUrl}
  OMP config:   ${statePath}

Start sharing from a new OMP session on this machine:

  /collab

Existing OMP sessions do not reload config; use this there:

  /collab ${relayUrl}

Guests join from a terminal with the link /collab prints, e.g.:

  omp join "<link>"

Terminal-only v1: browser click-to-join and QR links are NOT supported,
and /share self-hosting is disabled.

The public URL stays reachable until this command stops.
Stop with Ctrl-C to tear down both the relay and the tunnel.
`);
}
// The relay server (and cloudflared child, if any) keeps the process alive.
