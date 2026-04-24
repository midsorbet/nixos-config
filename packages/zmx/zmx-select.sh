#!/usr/bin/env bash
set -o pipefail

main() {
  local display output rc query key selected session_name

  display=$(
    zmx list 2>/dev/null | while IFS=$'\t' read -r name pid clients _created dir; do
      name=${name#session_name=}
      pid=${pid#pid=}
      clients=${clients#clients=}
      dir=${dir#started_in=}
      printf "%-20s  pid:%-8s  clients:%-2s  %s\n" "$name" "$pid" "$clients" "$dir"
    done
  )

  output=$(
    { [[ -n "$display" ]] && printf '%s\n' "$display"; } | fzf \
      --print-query \
      --expect=ctrl-n \
      --height=80% \
      --reverse \
      --prompt="zmx> " \
      --header="Enter: select | Ctrl-N: create new" \
      --preview='zmx history {1}' \
      --preview-window=right:60%:follow
  )
  rc=$?

  query=$(sed -n '1p' <<<"$output")
  key=$(sed -n '2p' <<<"$output")
  selected=$(sed -n '3p' <<<"$output")

  if [[ "$key" == "ctrl-n" && -n "$query" ]]; then
    session_name="$query"
  elif [[ $rc -eq 0 && -n "$selected" ]]; then
    session_name=$(awk '{print $1}' <<<"$selected")
  elif [[ -n "$query" ]]; then
    session_name="$query"
  else
    return 130
  fi

  zmx attach "$session_name"
}

main "$@"
