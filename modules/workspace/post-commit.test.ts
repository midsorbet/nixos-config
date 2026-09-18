import { afterEach, expect, test } from "bun:test";
import {
  chmodSync,
  copyFileSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const hook = join(import.meta.dir, "post-commit.sh");
const fixtures: string[] = [];
const env = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith("GIT_")),
);
Object.assign(env, {
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_TERMINAL_PROMPT: "0",
  GIT_AUTHOR_NAME: "Workspace fixture",
  GIT_AUTHOR_EMAIL: "fixture@localhost",
  GIT_COMMITTER_NAME: "Workspace fixture",
  GIT_COMMITTER_EMAIL: "fixture@localhost",
});

function git(cwd: string, ...args: string[]) {
  const result = Bun.spawnSync(["git", ...args], { cwd, env });
  if (result.exitCode !== 0) {
    throw new Error(
      `git ${args.join(" ")} failed: ${result.stderr.toString().trim()}`,
    );
  }
  return result.stdout.toString().trim();
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("publishes only the resolved upstream with an option-like remote name", () => {
  const root = mkdtempSync(join(tmpdir(), "post-commit-upstream-"));
  fixtures.push(root);
  const repo = join(root, "project");
  const backup = join(root, "backup.git");

  git(root, "init", "--bare", backup);
  git(root, "init", "--initial-branch=main", repo);
  writeFileSync(join(repo, "tracked.txt"), "initial\n");
  git(repo, "add", "tracked.txt");
  git(repo, "commit", "-m", "initial");
  git(repo, "remote", "add", "--", "--backup", backup);
  git(repo, "push", "--set-upstream", "--", "--backup", "main");
  git(repo, "config", "--add", "branch.main.merge", "refs/heads/other");

  const installedHook = join(repo, ".git", "hooks", "post-commit");
  copyFileSync(hook, installedHook);
  chmodSync(installedHook, 0o755);

  writeFileSync(join(repo, "tracked.txt"), "published\n");
  git(repo, "add", "tracked.txt");
  git(repo, "commit", "-m", "publish");

  expect(git(repo, "rev-parse", "@{upstream}")).toBe(git(repo, "rev-parse", "HEAD"));
  expect(git(backup, "rev-parse", "refs/heads/main")).toBe(
    git(repo, "rev-parse", "HEAD"),
  );
  expect(
    Bun.spawnSync(["git", "show-ref", "--verify", "--quiet", "refs/heads/other"], {
      cwd: backup,
      env,
    }).exitCode,
  ).toBe(1);
});
