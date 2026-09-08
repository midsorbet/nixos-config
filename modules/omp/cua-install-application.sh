set -euo pipefail

cua_package="@CUA_PACKAGE@"
cua_user="@CUA_USER@"
source_app="$cua_package/Applications/CuaDriver.app"
target_app='/Applications/CuaDriver.app'
marker_dir='/Library/Application Support/nix-cua-driver'
marker_file="$marker_dir/managed-source"
marker_temp=''

signature_details() {
  /usr/bin/codesign -dvvv "$1" 2>&1
}

verify_release() {
  local app="$1"
  local details

  /usr/bin/codesign --verify --deep --strict "$app"
  details="$(signature_details "$app")"
  /usr/bin/grep -Fqx 'Identifier=com.trycua.driver' <<<"$details"
  /usr/bin/grep -Fqx 'TeamIdentifier=YCK386LBJ7' <<<"$details"
}

cdhash() {
  signature_details "$1" | /usr/bin/sed -n 's/^CDHash=//p' | /usr/bin/head -n 1
}

stop_installed_daemon() {
  local driver="$target_app/Contents/MacOS/cua-driver"
  local stop_output
  local status_code

  if [[ ! -x "$driver" ]]; then
    echo >&2 'Cua Driver activation refused: the installed application has no executable driver to stop.'
    return 77
  fi

  if stop_output="$(/usr/bin/sudo -u "$cua_user" -H /usr/bin/env \
    CUA_DRIVER_RS_TELEMETRY_ENABLED=false \
    CUA_DRIVER_RS_UPDATE_CHECK=false \
    "$driver" stop 2>&1)"; then
    return 0
  fi

  set +e
  /usr/bin/sudo -u "$cua_user" -H /usr/bin/env \
    CUA_DRIVER_RS_TELEMETRY_ENABLED=false \
    CUA_DRIVER_RS_UPDATE_CHECK=false \
    "$driver" status >/dev/null 2>&1
  status_code=$?
  set -e
  if [[ "$status_code" -eq 1 ]]; then
    return 0
  fi

  printf >&2 'Cua Driver activation refused: stopping the installed user daemon failed:\n%s\n' "$stop_output"
  return 77
}

write_marker() {
  /bin/mkdir -p "$marker_dir"
  marker_temp="$(/usr/bin/mktemp "$marker_dir/.managed-source.XXXXXX")"
  printf '%s\n' "$cua_package" >"$marker_temp"
  /bin/chmod 0644 "$marker_temp"
  /bin/mv -f "$marker_temp" "$marker_file"
  marker_temp=''
}

verify_release "$source_app" || {
  echo >&2 'Cua Driver activation refused: the Nix-pinned application has an unexpected or invalid signing identity.'
  exit 77
}
source_hash="$(cdhash "$source_app")"
if [[ -z "$source_hash" ]]; then
  echo >&2 'Cua Driver activation refused: the Nix-pinned application has no signed CDHash.'
  exit 77
fi

target_hash=''
if [[ -e "$target_app" ]]; then
  verify_release "$target_app" || {
    echo >&2 'Cua Driver activation refused: /Applications/CuaDriver.app has an unexpected or invalid signing identity.'
    exit 77
  }
  target_hash="$(cdhash "$target_app")"
  if [[ -z "$target_hash" ]]; then
    echo >&2 'Cua Driver activation refused: /Applications/CuaDriver.app has no signed CDHash.'
    exit 77
  fi
  if [[ ! -f "$marker_file" && "$target_hash" != "$source_hash" ]]; then
    echo >&2 'Cua Driver activation refused: /Applications/CuaDriver.app is unmanaged and conflicts with the Nix-pinned release.'
    exit 77
  fi
  stop_installed_daemon
fi

if [[ -e "$target_app" && "$target_hash" == "$source_hash" ]]; then
  write_marker
  exit 0
fi

staging_dir="$(/usr/bin/mktemp -d /Applications/.CuaDriver.app.nix-new.XXXXXX)"
staging_app="$staging_dir/CuaDriver.app"
backup=''
original_moved=0
replacement_installed=0
rollback() {
  local result=$?
  trap - EXIT INT TERM HUP
  if [[ "$replacement_installed" -eq 1 ]]; then
    /bin/rm -rf -- "$target_app"
  fi
  if [[ "$original_moved" -eq 1 ]]; then
    /bin/mv -- "$backup" "$target_app"
  fi
  [[ -z "$marker_temp" || ! -e "$marker_temp" ]] || /bin/rm -f -- "$marker_temp"
  [[ ! -e "$staging_dir" ]] || /bin/rm -rf -- "$staging_dir"
  [[ -z "$backup" || ! -e "$backup" ]] || /bin/rm -rf -- "$backup"
  exit "$result"
}
trap rollback EXIT INT TERM HUP

/usr/bin/ditto "$source_app" "$staging_app"
verify_release "$staging_app"
[[ "$(cdhash "$staging_app")" == "$source_hash" ]]

if [[ -e "$target_app" ]]; then
  backup="$(/usr/bin/mktemp -d /Applications/.CuaDriver.app.nix-old.XXXXXX)"
  /bin/rmdir "$backup"
  /bin/mv -- "$target_app" "$backup"
  original_moved=1
fi
/bin/mv -- "$staging_app" "$target_app"
replacement_installed=1
write_marker

if [[ "$original_moved" -eq 1 ]]; then
  /bin/rm -rf -- "$backup"
  original_moved=0
fi
replacement_installed=0
/bin/rm -rf -- "$staging_dir"
trap - EXIT INT TERM HUP
