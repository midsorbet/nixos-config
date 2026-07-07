import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "bun:test";
import { clearTunnelState, collabConfigOverlay, defaultStateDir, statePaths, writeTunnelState, STATE_DIR_ENV } from "./state";

let tmpDir: string | null = null;

async function tempStateDir(): Promise<string> {
	tmpDir = await mkdtemp(path.join(os.tmpdir(), "omp-collab-state-test-"));
	return tmpDir;
}

afterEach(async () => {
	if (tmpDir) await rm(tmpDir, { force: true, recursive: true });
	tmpDir = null;
});

describe("omp-collab-tunnel state", () => {
	it("uses the explicit state-dir environment override before the macOS cache default", () => {
		expect(defaultStateDir({ [STATE_DIR_ENV]: "/tmp/omp-state" }, "/Users/alice")).toBe("/tmp/omp-state");
		expect(defaultStateDir({}, "/Users/alice")).toBe("/Users/alice/Library/Application Support/omp-collab-tunnel");
	});

	it("writes an OMP config overlay and pid for wrapper-gated default /collab", async () => {
		const stateDir = await tempStateDir();
		const paths = await writeTunnelState("wss://quick-example.trycloudflare.com", stateDir, 12345);

		expect(paths).toEqual(statePaths(stateDir));
		expect(await readFile(paths.config, "utf8")).toBe(collabConfigOverlay("wss://quick-example.trycloudflare.com"));
		expect(await readFile(paths.pid, "utf8")).toBe("12345\n");
	});

	it("refuses non-wss relay overlays", () => {
		expect(() => collabConfigOverlay("ws://127.0.0.1:7475")).toThrow(/invalid collab relay URL/);
		expect(() => collabConfigOverlay("https://quick-example.trycloudflare.com")).toThrow(/invalid collab relay URL/);
	});

	it("clears the overlay and pid idempotently", async () => {
		const stateDir = await tempStateDir();
		const paths = await writeTunnelState("wss://quick-example.trycloudflare.com", stateDir, 12345);

		await clearTunnelState(stateDir);
		await clearTunnelState(stateDir);

		await expect(Bun.file(paths.config).exists()).resolves.toBe(false);
		await expect(Bun.file(paths.pid).exists()).resolves.toBe(false);
	});
});
