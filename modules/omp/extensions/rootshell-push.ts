import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, join } from 'node:path';
import type { ExtensionAPI } from '@oh-my-pi/pi-coding-agent';

const ROOTSHELL_NOTIFY_EXECUTABLE = '@ROOTSHELL_NOTIFY_EXECUTABLE@';
const ROOTSHELL_PUSH_CONFIG =
  process.env.ROOTSHELL_PUSH_CONFIG ?? join(homedir(), '.config', 'rootshell-push', 'config.json');
const INPUT_TOOL_NAMES: Record<string, true> = {
  ask: true,
  'functions.ask': true,
};

type RootshelNotificationStatus = 'blocked' | 'done';

/** Sends one encrypted Rootshel push without delaying or failing the OMP event. */
function sendRootshelPush(
  pi: ExtensionAPI,
  cwd: string,
  body: string,
  status: RootshelNotificationStatus,
): void {
  if (!existsSync(ROOTSHELL_PUSH_CONFIG)) return;

  const args = [
    'send',
    '--title',
    `OMP · ${basename(cwd)}`,
    '--body',
    body,
    '--status',
    status,
  ];
  if (status === 'blocked') args.push('--priority', 'high');

  void pi.exec(ROOTSHELL_NOTIFY_EXECUTABLE, args, { cwd, timeout: 65_000 }).catch(() => {});
}

/** Reports settled OMP turns and requests for user input to Rootshel. */
export default function registerRootshelPushNotifications(pi: ExtensionAPI): void {
  pi.on('session_stop', (_event, ctx) => {
    sendRootshelPush(pi, ctx.cwd, 'Turn finished', 'done');
  });

  pi.on('tool_approval_requested', (event, ctx) => {
    sendRootshelPush(pi, ctx.cwd, `Approval needed for ${event.toolName}`, 'blocked');
  });

  pi.on('tool_call', (event, ctx) => {
    if (!INPUT_TOOL_NAMES[event.toolName]) return;
    sendRootshelPush(pi, ctx.cwd, 'Waiting for your answer', 'blocked');
  });
}
