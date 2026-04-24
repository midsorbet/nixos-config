#!/usr/bin/env bash
set -o pipefail

format_sessions() {
  zmx list 2>/dev/null | awk -F '\t' '
    {
      name = ""; pid = ""; clients = ""; dir = "";
      for (i = 1; i <= NF; i++) {
        field = $i;
        sub(/^[[:space:]]+/, "", field);
        key = field;
        sub(/=.*/, "", key);
        value = field;
        sub(/^[^=]*=/, "", value);

        if (key == "name" || key == "session_name") name = value;
        else if (key == "pid") pid = value;
        else if (key == "clients") clients = value;
        else if (key == "start_dir" || key == "started_in") dir = value;
      }

      if (name != "") {
        printf "%s\t%-24s  pid:%-8s  clients:%-2s  %s\n", name, name, pid, clients, dir;
      }
    }
  '
}

main() {
  local output rc query key selected session_name
  local -a lines

  output=$(
    format_sessions | fzf \
      --print-query \
      --expect=ctrl-n \
      --height=80% \
      --reverse \
      --prompt="zmx> " \
      --header="Enter: select | Ctrl-N: create new" \
      --delimiter=$'\t' \
      --with-nth=2.. \
      --preview='zmx history {1}' \
      --preview-window=right:60%:follow
  )
  rc=$?

  mapfile -t lines <<<"$output"
  query=${lines[0]:-}
  key=${lines[1]:-}
  selected=${lines[2]:-}

  if [[ "$key" != "ctrl-n" && -z "$selected" ]]; then
    selected="$key"
  fi

  if [[ "$key" == "ctrl-n" && -n "$query" ]]; then
    session_name="$query"
  elif [[ $rc -eq 0 && -n "$selected" ]]; then
    session_name=${selected%%$'\t'*}
  elif [[ -n "$query" ]]; then
    session_name="$query"
  else
    return 130
  fi

  exec zmx attach "$session_name"
}

main "$@"
