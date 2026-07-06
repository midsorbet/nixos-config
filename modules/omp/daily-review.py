#!/usr/bin/env python3
"""Collect today's user-started OMP sessions and build a review prompt.

This script is intentionally dumb: it only selects candidate session transcripts and
writes a prompt for `omp -p`. The agent that receives the prompt does the actual
judgement and file updates under tight written constraints.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class SessionSummary:
    path: Path
    started_at: dt.datetime
    local_date: dt.date
    title: str
    cwd: str
    first_user_text: str
    user_message_count: int
    assistant_message_count: int
    tool_call_count: int


def parse_timestamp(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone()


def text_from_content(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            parts.append(str(item.get("text") or ""))
    return "\n".join(part for part in parts if part).strip()


def session_timestamp_from_name(path: Path) -> dt.datetime | None:
    # OMP session names begin with a UTC ISO-ish stamp such as
    # 2026-07-05T03-45-48-454Z_<uuid>.jsonl.
    prefix = path.name.split("_", 1)[0]
    if not prefix.endswith("Z"):
        return None
    try:
        date_part, time_part = prefix[:-1].split("T", 1)
        hh, mm, ss, millis = time_part.split("-", 3)
        normalized = f"{date_part}T{hh}:{mm}:{ss}.{millis}+00:00"
        return dt.datetime.fromisoformat(normalized).astimezone()
    except ValueError:
        return None


def summarize_session(path: Path) -> SessionSummary | None:
    session: dict[str, Any] | None = None
    title: str | None = None
    first_user: dict[str, Any] | None = None
    user_message_count = 0
    assistant_message_count = 0
    tool_call_count = 0

    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        print(f"warning: cannot read {path}: {exc}", file=sys.stderr)
        return None

    for line in lines:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        obj_type = obj.get("type")
        if obj_type == "session":
            session = obj
        elif obj_type == "title" and obj.get("title"):
            title = str(obj["title"])
        elif obj_type == "message":
            message = obj.get("message") or {}
            role = message.get("role")
            if role == "user":
                user_message_count += 1
                if first_user is None:
                    first_user = message
            elif role == "assistant":
                assistant_message_count += 1
                for item in message.get("content") or []:
                    if isinstance(item, dict) and item.get("type") == "toolCall":
                        tool_call_count += 1

    if not first_user or first_user.get("attribution") != "user":
        return None

    first_user_text = text_from_content(first_user.get("content"))
    if not first_user_text:
        return None

    started_at = None
    if session:
        started_at = parse_timestamp(str(session.get("timestamp") or ""))
    if started_at is None:
        started_at = session_timestamp_from_name(path)
    if started_at is None:
        print(f"warning: cannot determine session timestamp for {path}", file=sys.stderr)
        return None

    resolved_title = title or str((session or {}).get("title") or "Untitled OMP session")
    cwd = str((session or {}).get("cwd") or path.parent.name)
    return SessionSummary(
        path=path,
        started_at=started_at,
        local_date=started_at.date(),
        title=resolved_title,
        cwd=cwd,
        first_user_text=first_user_text,
        user_message_count=user_message_count,
        assistant_message_count=assistant_message_count,
        tool_call_count=tool_call_count,
    )


def truncate(value: str, max_chars: int = 900) -> str:
    value = " ".join(value.split())
    if len(value) <= max_chars:
        return value
    return value[: max_chars - 1].rstrip() + "…"


def build_prompt(target_date: dt.date, sessions: list[SessionSummary], report_path: Path) -> str:
    bullets = []
    for idx, session in enumerate(sessions, start=1):
        bullets.append(
            "\n".join(
                [
                    f"{idx}. {session.title}",
                    f"   - transcript: `{session.path}`",
                    f"   - started_local: `{session.started_at.isoformat(timespec='seconds')}`",
                    f"   - cwd: `{session.cwd}`",
                    f"   - counts: user={session.user_message_count}, assistant={session.assistant_message_count}, tool_calls={session.tool_call_count}",
                    f"   - first_user_prompt: {truncate(session.first_user_text)}",
                ]
            )
        )

    return f"""# Daily OMP thread review for {target_date.isoformat()}

You are running as an unattended end-of-day maintenance pass for the user's own OMP/PyOMP sessions.

## Candidate sessions

These sessions were selected because their local start date is `{target_date.isoformat()}` and their first user-authored message has `attribution: user` in the OMP JSONL transcript. Review all of them; ignore sessions that are just slash-command noise or contain no durable learning.

{chr(10).join(bullets)}

## Required outcome

Evaluate how today's explicit user-started OMP/PyOMP threads went, then update future-session instructions only when the transcript gives strong evidence.

Write a concise run report to:

`{report_path}`

The report must include:

- sessions reviewed, with transcript paths;
- what went well;
- what went poorly or caused avoidable friction;
- concrete instruction/memory/skill updates applied;
- proposed follow-ups you deliberately did not apply.

## Allowed writes

Prefer small Markdown edits. Allowed write targets are:

- `/Users/me/vault/INBOX.md`
- `/Users/me/vault/planner/**/*.md`
- `/Users/me/vault/projects/*.md`
- `/Users/me/vault/areas/*.md`
- `/Users/me/vault/AGENTS.md`
- `/Users/me/.codex/AGENTS.md`
- `/Users/me/.codex/skills/*/SKILL.md`
- `/Users/me/.agents/skills/*/SKILL.md` only if the file is not a Nix-store symlink or generated package output.

Do not edit source checkouts under `/Users/me/vault/projects/<repo>/` automatically. If a source-repo `AGENTS.md`, package, module, test, or script should change, record an explicit proposed patch or follow-up in the run report instead.

## Decision rules

- Ground every update in transcript evidence. Do not promote a one-off accident into a permanent rule unless it prevented completion or clearly repeats prior instructions.
- Preserve unrelated user changes. Do not reorganize notes or skills just because you opened them.
- Do not copy secrets, tokens, raw private documents, or full transcript dumps into vault notes.
- Prefer updating the smallest relevant project/area note over adding global instructions.
- If no durable update is warranted, write the run report and say no instruction changes were applied.
- Do not run shell commands. Use only file read/search/edit/write tools.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sessions-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--date", help="Local date to review, YYYY-MM-DD. Defaults to today.")
    parser.add_argument("--lookback-hours", type=int, default=0, help="Optional fallback window when --date is not used. 0 means calendar day only.")
    parser.add_argument("--max-threads", type=int, default=20)
    args = parser.parse_args()

    now = dt.datetime.now().astimezone()
    target_date = dt.date.fromisoformat(args.date) if args.date else now.date()
    min_started_at = now - dt.timedelta(hours=args.lookback_hours) if args.lookback_hours > 0 else None

    sessions: list[SessionSummary] = []
    for path in args.sessions_dir.glob("*/*.jsonl"):
        summary = summarize_session(path)
        if summary is None:
            continue
        if summary.local_date == target_date or (min_started_at and summary.started_at >= min_started_at):
            sessions.append(summary)

    sessions.sort(key=lambda item: item.started_at)
    if len(sessions) > args.max_threads:
        sessions = sessions[-args.max_threads :]

    if not sessions:
        return 0

    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)
    prompt_path = args.output_dir / f"{target_date.isoformat()}.md"
    report_path = args.report_dir / f"{target_date.isoformat()}.md"
    prompt_path.write_text(build_prompt(target_date, sessions, report_path), encoding="utf-8")
    print(prompt_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
