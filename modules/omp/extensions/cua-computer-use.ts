import type { ExtensionAPI, ExtensionContext } from '@oh-my-pi/pi-coding-agent';
import cuaNativeToolNames from '../cua-native-tools.json' with { type: 'json' };

const CUA_DRIVER_SERVER_NAME = 'cua-driver';
const CUA_DRIVER_TOOL_NAME_PREFIX = 'mcp__cua_driver_';
const CUA_GATE_TOOL_NAME = 'cua_computer_use';
const CUA_MCP_CLIENT_MODULE = '@CUA_MCP_CLIENT@';
const CUA_MCP_LAUNCHER = '@CUA_MCP_LAUNCHER@';
const CUA_ALLOWED_APP_IDS_JSON = '@CUA_ALLOWED_APP_IDS@';
const CUA_STATUS_KEY = 'cua-computer-use-lease';
const CUA_STATUS_TEXT = 'cua: armed for this agent run';
const CUA_NATIVE_TOOL_NAME_SET = new Set<string>(cuaNativeToolNames);
const CUA_REGISTERED_TOOL_NAME_SET = new Set(
  cuaNativeToolNames.map((toolName) => `${CUA_DRIVER_TOOL_NAME_PREFIX}${toolName}`),
);

type CuaMcpContent =
  | { type: 'text'; text: string }
  | { type: 'image'; data: string; mimeType: string };

interface CuaMcpTool {
  name: string;
  description?: string;
  inputSchema: unknown;
}

interface CuaMcpToolResult {
  content: CuaMcpContent[];
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}

interface CuaMcpClient {
  listTools(): Promise<CuaMcpTool[]>;
  callTool(name: string, args: unknown, signal?: AbortSignal): Promise<CuaMcpToolResult>;
  close(): Promise<void>;
}

export type CuaMcpClientLoader = (signal?: AbortSignal) => Promise<CuaMcpClient>;

/** Load and connect the native Cua MCP client only after explicit computer-use activation. */
export async function loadCuaMcpClient(signal?: AbortSignal): Promise<CuaMcpClient> {
  signal?.throwIfAborted();
  // Static import cannot work: the Nix integration substitutes this runtime module placeholder.
  const clientModule: { connectCuaMcp(command: string, signal?: AbortSignal): Promise<CuaMcpClient> } =
    await import(CUA_MCP_CLIENT_MODULE);
  signal?.throwIfAborted();
  return clientModule.connectCuaMcp(CUA_MCP_LAUNCHER, signal);
}

/** Narrow an untrusted MCP input schema to the raw JSON Schema accepted by OMP. */
function isCuaJsonInputSchema(schema: unknown): schema is Record<string, unknown> {
  if (schema === null || typeof schema !== 'object' || Array.isArray(schema)) return false;
  const candidate = schema as Record<string, unknown>;
  if (candidate.type !== 'object') return false;
  if (
    candidate.properties !== undefined &&
    (candidate.properties === null ||
      typeof candidate.properties !== 'object' ||
      Array.isArray(candidate.properties))
  ) {
    return false;
  }
  return (
    candidate.required === undefined ||
    (Array.isArray(candidate.required) && candidate.required.every((name) => typeof name === 'string'))
  );
}

/** Enforce the exact configured app identity before any native Cua launch dispatch. */
function assertCuaLaunchScope(args: unknown, allowedAppBundleIds: ReadonlySet<string>): void {
  if (args === null || typeof args !== 'object' || Array.isArray(args)) {
    throw new Error('Cua launch scope guard rejected launch_app: require an allowed explicit bundle_id.');
  }
  const launchArgs = args as Record<string, unknown>;
  const hasAlternateIdentity = ['name', 'path', 'target', 'launch_path'].some((field) =>
    Object.hasOwn(launchArgs, field),
  );
  if (
    !Object.hasOwn(launchArgs, 'bundle_id') ||
    typeof launchArgs.bundle_id !== 'string' ||
    !allowedAppBundleIds.has(launchArgs.bundle_id) ||
    hasAlternateIdentity
  ) {
    throw new Error(
      'Cua launch scope guard rejected launch_app: require an allowed explicit bundle_id and no alternate app identity fields.',
    );
  }
}

/** Publish optional lease status without making authorization depend on UI rendering. */
function publishCuaLeaseStatus(
  ui: ExtensionContext['ui'] | undefined,
  text: string | undefined,
): void {
  try {
    ui?.setStatus?.(CUA_STATUS_KEY, text);
  } catch {
    // Cua authorization remains fail-closed if optional status rendering fails.
  }
}

/** Register a lazy native Cua Driver gate; no client code or catalog loads before activation. */
export default function registerCuaComputerUse(
  pi: ExtensionAPI,
  loadClient: CuaMcpClientLoader = loadCuaMcpClient,
  allowedAppBundleIds: readonly string[] = JSON.parse(CUA_ALLOWED_APP_IDS_JSON),
): void {
  let leaseActive = false;
  let leaseGeneration = 0;
  let leaseClient: CuaMcpClient | undefined;
  let leaseStatusUi: ExtensionContext['ui'] | undefined;
  let activeToolMutation = Promise.resolve();
  const registeredNativeToolNames = new Set<string>();
  const allowedAppBundleIdSet = new Set(allowedAppBundleIds);
  const runActiveToolMutation = <T>(mutation: () => Promise<T>): Promise<T> => {
    const result = activeToolMutation.then(mutation);
    activeToolMutation = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  };

  const revokeLease = async (): Promise<void> => {
    ++leaseGeneration;
    leaseActive = false;
    const client = leaseClient;
    leaseClient = undefined;
    publishCuaLeaseStatus(leaseStatusUi, undefined);
    leaseStatusUi = undefined;

    try {
      await runActiveToolMutation(async () => {
        const activeToolNames = pi.getActiveTools();
        const remainingToolNames = activeToolNames.filter(
          (name) => !registeredNativeToolNames.has(name),
        );
        if (remainingToolNames.length !== activeToolNames.length) {
          await pi.setActiveTools(remainingToolNames);
        }
      });
    } finally {
      await client?.close();
    }
  };

  pi.on('session_start', revokeLease);
  pi.on('before_agent_start', async (_event, ctx) => {
    await revokeLease();
    return { systemPrompt: ctx.getSystemPrompt() };
  });
  pi.on('agent_end', revokeLease);
  pi.on('session_stop', revokeLease);
  pi.on('session_shutdown', revokeLease);

  // Registered definitions cannot be removed, so this synchronous gate keeps inactive leases fail-closed.
  pi.on('tool_call', (event) => {
    if (CUA_REGISTERED_TOOL_NAME_SET.has(event.toolName) && !leaseActive) {
      return {
        block: true,
        reason: 'Cua computer use is not armed. Call cua_computer_use first.',
      };
    }
  });

  pi.registerTool({
    name: CUA_GATE_TOOL_NAME,
    label: 'Arm Cua Computer Use',
    description:
      'Connect to Cua Driver and expose its native tools for this agent run. The lease closes at agent end.',
    parameters: pi.zod.object({}),
    approval: 'exec',
    loadMode: 'essential',
    strict: true,
    async execute(_toolCallId, _params, signal, _onUpdate, ctx) {
      signal?.throwIfAborted();
      await revokeLease();
      signal?.throwIfAborted();
      const activationGeneration = ++leaseGeneration;
      let client: CuaMcpClient | undefined;

      try {
        client = await loadClient(signal);
        signal?.throwIfAborted();
        const discoveredTools = await client.listTools();
        signal?.throwIfAborted();

        const allowedTools = new Map<string, CuaMcpTool>();
        for (const tool of discoveredTools) {
          if (CUA_NATIVE_TOOL_NAME_SET.has(tool.name)) allowedTools.set(tool.name, tool);
        }
        const missingTools = cuaNativeToolNames.filter((name) => !allowedTools.has(name));
        if (missingTools.length > 0) {
          throw new Error(
            `Cua MCP capability contract is incomplete; missing native tools: ${missingTools.join(', ')}.`,
          );
        }
        for (const toolName of cuaNativeToolNames) {
          const schema = allowedTools.get(toolName)?.inputSchema;
          if (!isCuaJsonInputSchema(schema)) {
            throw new Error(`Cua MCP tool ${toolName} returned an invalid input schema.`);
          }
        }
        if (activationGeneration !== leaseGeneration) {
          throw new Error('Cua computer use activation was superseded by lease revocation.');
        }

        for (const nativeToolName of cuaNativeToolNames) {
          const tool = allowedTools.get(nativeToolName)!;
          const registeredToolName = `${CUA_DRIVER_TOOL_NAME_PREFIX}${nativeToolName}`;
          pi.registerTool({
            name: registeredToolName,
            label: tool.description ?? nativeToolName,
            description: tool.description ?? `Native Cua Driver tool: ${nativeToolName}`,
            parameters: tool.inputSchema as Record<string, unknown>,
            defaultInactive: true,
            approval: 'exec',
            mcpServerName: CUA_DRIVER_SERVER_NAME,
            mcpToolName: nativeToolName,
            async execute(_nativeCallId, args, callSignal) {
              if (!leaseActive || !leaseClient) {
                throw new Error('Cua native tool call rejected: the computer-use lease is inactive.');
              }
              callSignal?.throwIfAborted();
              if (nativeToolName === 'launch_app') {
                assertCuaLaunchScope(args, allowedAppBundleIdSet);
              }
              const result = await leaseClient.callTool(nativeToolName, args, callSignal);
              return {
                content: result.content,
                details: result.structuredContent,
                ...(result.isError === true ? { isError: true } : {}),
              };
            },
          });
          registeredNativeToolNames.add(registeredToolName);
        }

        await runActiveToolMutation(async () => {
          signal?.throwIfAborted();
          if (activationGeneration !== leaseGeneration) {
            throw new Error('Cua computer use activation was superseded by lease revocation.');
          }
          const activeToolNames = pi.getActiveTools();
          const missingActiveTools = [...registeredNativeToolNames].filter(
            (name) => !activeToolNames.includes(name),
          );
          if (missingActiveTools.length > 0) {
            await pi.setActiveTools([...activeToolNames, ...missingActiveTools]);
          }
          signal?.throwIfAborted();
          if (activationGeneration !== leaseGeneration) {
            throw new Error('Cua computer use activation was superseded by lease revocation.');
          }
        });

        leaseClient = client;
        client = undefined;
        leaseActive = true;
        leaseStatusUi = ctx.ui;
        publishCuaLeaseStatus(leaseStatusUi, CUA_STATUS_TEXT);
        return {
          content: [{ type: 'text' as const, text: 'Native Cua Driver MCP tools are armed for this agent run.' }],
          details: {
            armed: true,
            server: CUA_DRIVER_SERVER_NAME,
            toolCount: registeredNativeToolNames.size,
          },
        };
      } catch (error) {
        await client?.close();
        if (activationGeneration === leaseGeneration) await revokeLease();
        throw error;
      }
    },
  });
}
