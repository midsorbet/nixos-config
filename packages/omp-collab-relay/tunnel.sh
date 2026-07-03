# omp-collab-tunnel — on-demand OMP collab sharing through a Cloudflare
# Quick Tunnel. Body for writeShellApplication: strict mode and PATH
# (omp-collab-relay, cloudflared, curl, coreutils, gnugrep) come from Nix.

usage() {
  cat <<'EOF'
usage: omp-collab-tunnel [--port PORT] [--bind ADDR] [--idle-timeout-secs N]

Starts a hardened loopback-only OMP collab relay plus a temporary Cloudflare
Quick Tunnel, then prints the /collab command for the session.

Options:
  --port PORT              Relay listen port (default 7475,
                           env OMP_COLLAB_RELAY_PORT).
  --bind ADDR              Relay listen address; loopback addresses only
                           (default 127.0.0.1).
  --idle-timeout-secs N    Relay idle room teardown, forwarded to
                           omp-collab-relay (default 1800).
  -h, --help               Show this help.

Notes:
  - The printed wss://...trycloudflare.com URL is public internet attack
    surface while this command runs. Share the /collab link only with the
    intended guest; prefer "/collab view" for lower-trust observers.
  - Terminal-only v1: browser click-to-join and QR links are NOT supported
    (GET / serves no client), and /share self-hosting is disabled. Guests
    join from a terminal, e.g. omp join "<link>".
  - The relay is content-blind, but OMP's collab wire protocol (v3 as of
    16.3.x) is checked between host and guest: run matching OMP versions
    on both ends or the guest is rejected during handshake.
  - Quiet sessions are torn down by the relay after the idle timeout
    (default 30 minutes with no relayed traffic; connection liveness does
    not count). Raise --idle-timeout-secs for long passive sessions.
  - Stop with Ctrl-C to tear down both the relay and the tunnel.
EOF
}

port="${OMP_COLLAB_RELAY_PORT:-7475}"
bind="127.0.0.1"
idle_timeout=""

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "error: missing value for $1" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --port)
      require_value "$@"
      port="$2"
      shift
      ;;
    --port=*)
      port="${1#--port=}"
      ;;
    --bind)
      require_value "$@"
      bind="$2"
      shift
      ;;
    --bind=*)
      bind="${1#--bind=}"
      ;;
    --idle-timeout-secs)
      require_value "$@"
      idle_timeout="$2"
      shift
      ;;
    --idle-timeout-secs=*)
      idle_timeout="${1#--idle-timeout-secs=}"
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$port" in
  ""|*[!0-9]*)
    echo "error: --port must be numeric" >&2
    exit 2
    ;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo "error: --port must be between 1 and 65535" >&2
  exit 2
fi

# Keep the relay loopback-only; the relay enforces this too.
case "$bind" in
  127.*|localhost|::1) ;;
  *)
    echo "error: --bind must be a loopback address (127.x.y.z, localhost, or ::1)" >&2
    exit 2
    ;;
esac

case "$idle_timeout" in
  "") ;;
  0|*[!0-9]*)
    echo "error: --idle-timeout-secs must be a positive integer" >&2
    exit 2
    ;;
esac

probe_host="$bind"
if [ "$bind" = "::1" ]; then
  probe_host="[::1]"
fi

# Fail early if something else already owns the port (macOS lsof).
if [ -x /usr/sbin/lsof ]; then
  if /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port $port is already listening; pick another with --port" >&2
    exit 1
  fi
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/omp-collab-tunnel.XXXXXX")"
relay_pid=""
tunnel_pid=""

cleanup() {
  set +e
  for pid in "$tunnel_pid" "$relay_pid"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
    fi
  done
  rm -rf "$workdir"
}

# cloudflared's log format is outside this repo's control; redact anything
# that looks like a room path before showing it, so a proxy-error line can
# never leak `/r/<roomId>` connect capability.
dump_tunnel_log() {
  tail -n 40 "$workdir/cloudflared.log" 2>/dev/null \
    | sed -E 's#/r/[A-Za-z0-9_-]+[^[:space:]"]*#/r/<redacted>#g' >&2
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Relay logs go straight to this console: sparse join/leave events with
# truncated room ids only — no link material.
relay_args=(--port "$port" --bind "$bind")
if [ -n "$idle_timeout" ]; then
  relay_args+=(--idle-timeout-secs "$idle_timeout")
fi
omp-collab-relay "${relay_args[@]}" &
relay_pid="$!"

relay_ready=""
for _ in $(seq 1 40); do
  if curl -fsS --max-time 1 "http://$probe_host:$port/healthz" >/dev/null 2>&1; then
    relay_ready=1
    break
  fi
  if ! kill -0 "$relay_pid" 2>/dev/null; then
    echo "error: omp-collab-relay exited during startup" >&2
    exit 1
  fi
  sleep 0.5
done

if [ -z "$relay_ready" ]; then
  echo "error: omp-collab-relay did not become ready on $bind:$port" >&2
  exit 1
fi

# Quick Tunnel output is noisy; keep it in the workdir and only parse the
# generated hostname out of it.
cloudflared tunnel --no-autoupdate --url "http://$probe_host:$port" \
  >"$workdir/cloudflared.log" 2>&1 &
tunnel_pid="$!"

tunnel_url=""
for _ in $(seq 1 120); do
  tunnel_url="$(
    grep -Eo 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$workdir/cloudflared.log" 2>/dev/null \
      | grep -v '^https://api\.trycloudflare\.com$' \
      | head -n 1 || true
  )"
  if [ -n "$tunnel_url" ]; then
    break
  fi
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    echo "error: cloudflared exited during startup" >&2
    dump_tunnel_log
    exit 1
  fi
  sleep 0.5
done

if [ -z "$tunnel_url" ]; then
  echo "error: no trycloudflare.com URL appeared in cloudflared output" >&2
  dump_tunnel_log
  exit 1
fi

relay_url="wss://${tunnel_url#https://}"

tunnel_host="${tunnel_url#https://}"

check_children() {
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    echo "error: cloudflared exited while waiting for the public endpoint" >&2
    dump_tunnel_log
    exit 1
  fi
  if ! kill -0 "$relay_pid" 2>/dev/null; then
    echo "error: omp-collab-relay exited while waiting for the public endpoint" >&2
    exit 1
  fi
}

# Phase 1 (diagnostic only, never authoritative): check tunnel liveness at the
# Cloudflare edge without DNS, by connecting to the stable apex and letting
# SNI/Host route to the new hostname. Fresh trycloudflare.com names can take
# minutes to appear in DNS, and querying them too early can prime local
# negative caches (e.g. WARP/Gateway resolvers), so avoid DNS until the
# tunnel itself is confirmed up.
echo "waiting for the tunnel to come up at the Cloudflare edge..."
edge_live=""
for _ in $(seq 1 30); do
  code="$(
    curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
      --connect-to "$tunnel_host:443:trycloudflare.com:443" \
      "$tunnel_url/healthz" 2>/dev/null || true
  )"
  if [ "$code" = "200" ]; then
    edge_live=1
    break
  fi
  check_children
  sleep 2
done
if [ -n "$edge_live" ]; then
  echo "tunnel is live at the edge; waiting for public DNS..."
else
  echo "note: edge liveness probe did not confirm the tunnel; continuing to the DNS check..."
fi

# Phase 2 (authoritative): the printed URL is only useful once the hostname
# resolves through normal DNS — the same condition guests need.
dns_ready=""
for i in $(seq 1 24); do
  if curl -fsS --max-time 5 "$tunnel_url/healthz" >/dev/null 2>&1; then
    dns_ready=1
    break
  fi
  check_children
  if [ "$((i % 6))" -eq 0 ]; then
    echo "still waiting for public DNS ($((i * 5))s)..."
  fi
  sleep 5
done

if [ -z "$dns_ready" ]; then
  echo "warning: $tunnel_url/healthz is not reachable from this machine yet;" >&2
  echo "warning: DNS for fresh trycloudflare.com names can lag — the URL may still start working shortly." >&2
fi

cat <<EOF

OMP collab quick tunnel is live.

  Local relay:  http://$probe_host:$port  (loopback only)
  Public relay: $relay_url

Start sharing from an OMP session on this machine:

  /collab $relay_url

Guests join from a terminal with the link /collab prints, e.g.:

  omp join "<link>"

Terminal-only v1: browser click-to-join and QR links are NOT supported,
and /share self-hosting is disabled.

The public URL stays reachable until this command stops.
Stop with Ctrl-C to tear down both the relay and the tunnel.

EOF

while :; do
  if ! kill -0 "$relay_pid" 2>/dev/null; then
    echo "error: omp-collab-relay exited unexpectedly" >&2
    exit 1
  fi
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    echo "error: cloudflared exited unexpectedly" >&2
    dump_tunnel_log
    exit 1
  fi
  sleep 2
done
