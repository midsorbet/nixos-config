import { describe, expect, it } from 'bun:test';
import type { ExtensionAPI } from '@oh-my-pi/pi-coding-agent';
import cuaNativeToolNames from '../cua-native-tools.json' with { type: 'json' };
import registerCuaComputerUse, { type CuaMcpClientLoader } from './cua-computer-use';

const CUA_TOOL = `mcp__cua_driver_${cuaNativeToolNames[0]}`;
const CUA_LAUNCH_TOOL = 'mcp__cua_driver_launch_app';
const ALLOWED_APP_BUNDLE_ID = 'com.apple.TextEdit';
const FOREIGN_TOOL = 'mcp__cua_driver_foreign';
const OTHER_TOOL = 'read';

type EventHandler = (...args: unknown[]) => unknown;
type RegisteredTool = {
  name: string;
  defaultInactive?: boolean;
  execute: (...args: unknown[]) => Promise<unknown>;
};
type ActiveToolSetter = (names: string[], commit: (names: string[]) => void) => Promise<void>;
type NativeContent =
  | { type: 'text'; text: string }
  | { type: 'image'; data: string; mimeType: string };
type NativeToolResult = {
  content: NativeContent[];
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};
type NativeToolDescription = {
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
};

type FakeClient = {
  listTools: () => Promise<NativeToolDescription[]>;
  callTool: (name: string, args: unknown, signal?: AbortSignal) => Promise<NativeToolResult>;
  close: () => Promise<void>;
  closed: boolean;
  calls: Array<{ name: string; args: unknown; signal?: AbortSignal }>;
};

function makeClient(options: { missing?: boolean; delayList?: Promise<void> } = {}): FakeClient {
  const calls: FakeClient['calls'] = [];
  const client: FakeClient = {
    closed: false,
    calls,
    async listTools() {
      await options.delayList;
      return cuaNativeToolNames
        .filter((name) => !options.missing || name !== cuaNativeToolNames.at(-1))
        .map((name) => ({
          name,
          description: `native ${name}`,
          inputSchema: { type: 'object', properties: { value: { type: 'string' } } },
        }));
    },
    async callTool(name, args, signal) {
      calls.push({ name, args, signal });
      return {
        content: [
          { type: 'text', text: 'native text' },
          { type: 'image', data: 'aW1hZ2U=', mimeType: 'image/png' },
        ],
        structuredContent: { native: true },
      };
    },
    async close() {
      client.closed = true;
    },
  };
  return client;
}

function makeHarness(options: {
  loader?: CuaMcpClientLoader;
  active?: string[];
  setActiveTools?: ActiveToolSetter;
  allowedAppBundleIds?: readonly string[];
} = {}) {
  let activeTools = [...(options.active ?? [OTHER_TOOL])];
  const registeredTools: RegisteredTool[] = [];
  const handlers: Record<string, EventHandler> = {};
  const defaultSetActiveTools: ActiveToolSetter = async (names, commit) => commit(names);
  const setActiveTools = options.setActiveTools ?? defaultSetActiveTools;
  const pi = {
    zod: { object: () => ({}) },
    getActiveTools: () => [...activeTools],
    setActiveTools: (names: string[]) =>
      setActiveTools(names, (next) => {
        activeTools = [...next];
      }),
    on: (event: string, handler: EventHandler) => {
      handlers[event] = handler;
    },
    registerTool: (tool: unknown) => {
      registeredTools.push(tool as RegisteredTool);
    },
  } as unknown as ExtensionAPI;

  registerCuaComputerUse(pi, options.loader, options.allowedAppBundleIds ?? [ALLOWED_APP_BUNDLE_ID]);

  return {
    registeredTools,
    activeTools: () => [...activeTools],
    async emit(event: string, ...args: unknown[]) {
      await handlers[event]?.(...args);
    },
    toolCall(toolName: string) {
      return handlers.tool_call?.({ toolName });
    },
    async activate(signal?: AbortSignal) {
      const activator = registeredTools.find((tool) => tool.name === 'cua_computer_use');
      if (!activator) throw new Error('Cua activation tool was not registered.');
      return activator.execute('call-cua', {}, signal, undefined, { ui: undefined });
    },
    nativeTool(name: string = CUA_TOOL) {
      return registeredTools.find((tool) => tool.name === name);
    },
  };
}

describe('cua computer-use lazy gate', () => {
  it('registers only the activator and does not load or enumerate before activation', async () => {
    let loads = 0;
    const harness = makeHarness({
      loader: async () => {
        loads++;
        throw new Error('loader must not run');
      },
    });

    expect(loads).toBe(0);
    expect(harness.registeredTools.map((tool) => tool.name)).toEqual(['cua_computer_use']);
    expect(harness.activeTools()).toEqual([OTHER_TOOL]);
  });

  it('rejects a disallowed bundle identifier before native launch dispatch', async () => {
    const client = makeClient();
    const harness = makeHarness({ loader: async () => client });
    await harness.activate();

    await expect(
      harness
        .nativeTool(CUA_LAUNCH_TOOL)
        ?.execute('launch-call', { bundle_id: 'com.apple.systempreferences' }, undefined, undefined, {}),
    ).rejects.toThrow('Cua launch scope guard rejected launch_app');
    expect(client.calls).toEqual([]);
  });

  it('rejects a launch without an explicit bundle identifier before native dispatch', async () => {
    const client = makeClient();
    const harness = makeHarness({ loader: async () => client });
    await harness.activate();

    await expect(
      harness.nativeTool(CUA_LAUNCH_TOOL)?.execute('launch-call', {}, undefined, undefined, {}),
    ).rejects.toThrow('Cua launch scope guard rejected launch_app');
    expect(client.calls).toEqual([]);
  });

  it('rejects a conflicting app name even with an allowed bundle identifier', async () => {
    const client = makeClient();
    const harness = makeHarness({ loader: async () => client });
    await harness.activate();

    await expect(
      harness.nativeTool(CUA_LAUNCH_TOOL)?.execute(
        'launch-call',
        { bundle_id: ALLOWED_APP_BUNDLE_ID, name: 'System Settings' },
        undefined,
        undefined,
        {},
      ),
    ).rejects.toThrow('Cua launch scope guard rejected launch_app');
    expect(client.calls).toEqual([]);
  });

  it('revokes synchronously at agent end, closes the client, and allows a later activation', async () => {
    const firstClient = makeClient();
    const secondClient = makeClient();
    let nextClient = firstClient;
    const harness = makeHarness({ loader: async () => nextClient });

    await harness.activate();
    await harness.emit('agent_end');
    expect(harness.toolCall(CUA_TOOL)).toMatchObject({ block: true });
    expect(harness.activeTools()).toEqual([OTHER_TOOL]);
    expect(firstClient.closed).toBe(true);

    nextClient = secondClient;
    await harness.activate();
    expect(harness.toolCall(CUA_TOOL)).toBeUndefined();
    expect(harness.activeTools()).toContain(CUA_TOOL);
  });

  it('fails negotiation when a required native capability is missing and leaves the lease closed', async () => {
    const client = makeClient({ missing: true });
    const harness = makeHarness({ loader: async () => client });

    await expect(harness.activate()).rejects.toThrow('missing native tools');
    expect(client.closed).toBe(true);
    expect(harness.toolCall(CUA_TOOL)).toMatchObject({ block: true });
    expect(harness.activeTools()).toEqual([OTHER_TOOL]);
  });

  it('closes a stale aborted activation and cannot restore native tools after teardown', async () => {
    let releaseList!: () => void;
    const listReady = new Promise<void>((resolve) => {
      releaseList = resolve;
    });
    const client = makeClient({ delayList: listReady });
    let loaderReached!: () => void;
    const loaderReady = new Promise<void>((resolve) => {
      loaderReached = resolve;
    });
    const harness = makeHarness({
      loader: async () => {
        loaderReached();
        return client;
      },
    });
    const controller = new AbortController();
    const activation = harness.activate(controller.signal);

    await loaderReady;
    controller.abort();
    const teardown = harness.emit('agent_end');
    releaseList();

    await expect(activation).rejects.toThrow();
    await teardown;
    expect(client.closed).toBe(true);
    expect(harness.toolCall(CUA_TOOL)).toMatchObject({ block: true });
    expect(harness.activeTools()).not.toContain(CUA_TOOL);
  });

  it('preserves foreign tools sharing the cua-driver prefix', async () => {
    const client = makeClient();
    const harness = makeHarness({ loader: async () => client, active: [OTHER_TOOL, FOREIGN_TOOL] });

    expect(harness.toolCall(FOREIGN_TOOL)).toBeUndefined();
    await harness.activate();
    await harness.emit('agent_end');
    expect(harness.toolCall(FOREIGN_TOOL)).toBeUndefined();
    expect(harness.activeTools()).toEqual([OTHER_TOOL, FOREIGN_TOOL]);
  });
});
