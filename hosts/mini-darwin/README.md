# Mini Darwin Operating Boundaries

`hosts/mini-darwin/default.nix` owns the declarative implementation. Preserve the
following operational constraints when changing the desktop or personal-infra
services.

## Paneru

- The Dell landscape display is the work canvas and the Acer portrait display is
  the reference rail. Keep Paneru's portrait strip and landscape strip separate.
- Virtual workspace rows are unsafe on the upper landscape display while the
  portrait display is arranged below it: hidden rows overlap the lower display.
  Use virtual rows only on the lower portrait display, or move that display
  logically above the landscape display before enabling landscape rows.
- Paneru strips remain horizontal on every display. Vertical gestures select
  workspace rows; they do not create a portrait-oriented scrolling strip.

## Helium and browser routing

- Start Helium with a normal window so Paneru observes and tiles it. Do not add
  `--no-startup-window` to the browser-relay LaunchAgent.
- Keep Hister's Helium extension installation mutable until Helium supports the
  extension policy reliably. Do not leave a rejected mandatory policy installed.
- Finicky remains the default router: Firefox is the default browser and Helium
  is selected only for the explicitly managed sites and patterns. Do not add a
  manually maintained tracking-parameter rewrite list.

## Private search and backup

- Protect Hister with an access token stored only in the private secrets repo.
  The corpus is application data and belongs in the normal encrypted backups;
  only credentials belong in the secrets repo.
- Mini is the authoritative vault working copy. Syncthing is send-only on Mini
  and receive-only on Baymax; never edit the Baymax mirror. Exclude Git metadata,
  secrets, and regenerable outputs from that mirror.

## Hooh relay

- `herdr-relay` uses Python only for orchestration. Hetzner operations use
  `hcloud`; `frpc` and `frps` handle forwarding and reconnection.
- Activate the reviewed Mini and Baymax configurations before use. Baymax owns
  the minute-by-minute expiry reaper. Hooh also powers off at its lease deadline;
  only deletion ends server billing. No cloud resources are created by activation.
- After approving costs, run `herdr-relay prepare --flake /path/to/nixos-config`. It creates the retained IPv4/firewall and a NixOS snapshot, then deletes the temporary builder. The temporary builder has a fixed four-hour lease, established only when creation begins; slow preparation cannot extend it, and failures still clean up the owned builder.
  Configure a Cloudflare DNS-only A record for `mini.midsorbet.me` using the returned IPv4. Retired snapshots remain billable until explicitly deleted after verifying their replacement.
- Snapshots must match the expected Hooh system build as well as its trust identity.
  After changing Hooh configuration or server certificates, activate the reviewed
  Mini/Baymax configuration, then run `prepare` from the matching checkout.
  `start` refuses stale snapshots before creating a VPS; `prepare` refuses a
  checkout that differs from the activated expected build.
- Run `herdr-relay start --ttl 8h`, `herdr-relay status`, and `herdr-relay stop`.
  Start checks the forwarded Mini SSH host key before reporting readiness.
  Leases cannot exceed 12 hours; repeated starts never extend an existing lease.
  Terminal hangups unwind active preparation/start operations and attempt cleanup.
  Cleanup errors preserve the original failure; inspect `status` afterward.
  Invalid expiry labels remain visible in `status` but never authorize deletion.
- At work, use `herdr --remote ssh://me@mini.midsorbet.me:2222`, or a compatible
  Herdr version with `machine add`. No frp or Cloudflare client is needed there.
- Mutual TLS authenticates Mini to Hooh. SSH still authenticates the work user
  directly to Mini. Private keys and API credentials belong in `nix-secrets`;
  public certificates live in `hosts/hooh/`. Renew certificates before their
  `openssl x509 -in hosts/hooh/frp-server.crt -noout -enddate` expiry.
- Hooh uses its canonical SSH host key to decrypt only its server TLS key.
  The Hetzner API token is never deployed to Hooh.
  Preparation uses a fresh temporary SSH host key for Debian and the installer.
  The canonical private key is installed through the pinned SSH connection, never
  placed in cloud-init metadata. Post-install verification trusts only that
  canonical key.
