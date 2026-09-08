import type {
  CallToolResult,
  CompatibilityCallToolResult,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";

type NativeCallToolResult = CallToolResult | CompatibilityCallToolResult;

/** Client methods exposed to the Cua lazy activation gate. */
export type CuaMcpClient = {
  listTools(): Promise<Tool[]>;
  callTool(
    name: string,
    args: Record<string, unknown>,
    signal?: AbortSignal,
  ): Promise<NativeCallToolResult>;
  close(): Promise<void>;
};

const SAFE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin";

function abortReason(signal: AbortSignal): unknown {
  return signal.reason ?? new DOMException("The operation was aborted", "AbortError");
}

/** Connects once to a Cua MCP stdio server using the official MCP SDK. */
export async function connectCuaMcp(
  command: string,
  signal?: AbortSignal,
): Promise<CuaMcpClient> {
  if (signal?.aborted) {
    throw abortReason(signal);
  }

  const [{ Client }, { StdioClientTransport }] = await Promise.all([
    import("@modelcontextprotocol/sdk/client/index.js"),
    import("@modelcontextprotocol/sdk/client/stdio.js"),
  ]);
  if (signal?.aborted) {
    throw abortReason(signal);
  }

  const env = Object.freeze({
    HOME: process.env.HOME ?? "/tmp",
    USER: process.env.USER ?? "unknown",
    LOGNAME: process.env.LOGNAME ?? process.env.USER ?? "unknown",
    TMPDIR: process.env.TMPDIR ?? "/tmp",
    PATH: SAFE_PATH,
    CUA_DRIVER_RS_TELEMETRY_ENABLED: "false",
    CUA_DRIVER_RS_UPDATE_CHECK: "false",
  });
  const transport = new StdioClientTransport({
    command,
    env,
    stderr: "inherit",
  });
  const client = new Client({
    name: "omp-cua-mcp-client",
    version: "1.0.0",
  });

  let closePromise: Promise<void> | undefined;
  const close = (): Promise<void> => {
    if (closePromise === undefined) {
      closePromise = client.close();
    }
    return closePromise;
  };
  const closeOnAbort = (): void => {
    void close().catch(() => undefined);
  };
  signal?.addEventListener("abort", closeOnAbort, { once: true });

  try {
    await client.connect(transport, { signal });
    if (signal?.aborted) {
      await close();
      throw abortReason(signal);
    }

    return {
      listTools: async () => (await client.listTools()).tools,
      callTool: (name, args, callSignal) =>
        client.callTool({ name, arguments: args }, undefined, { signal: callSignal }),
      close,
    };
  } catch (error) {
    await close().catch(() => undefined);
    throw error;
  } finally {
    signal?.removeEventListener("abort", closeOnAbort);
  }
}
