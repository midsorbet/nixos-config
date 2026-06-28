# Baymax

## Live ISO

Append this to the kernel command line in the boot menu to avoid issues with the Seagate External HDD:

```text
usb-storage.quirks=0bc2:2344:u
```

- Highlight the ISO boot entry and press `e`.
- Append the quirk string to the Linux kernel command line.
- Boot with `Ctrl+x`

## Remote Unlock Setup

One-time setup:

```bash
sudo install -d -m 700 /persist/host/secrets/initrd
sudo ssh-keygen -t ed25519 -N "" -f /persist/host/secrets/initrd/ssh_host_ed25519_key
sudo chmod 600 /persist/host/secrets/initrd/ssh_host_ed25519_key
sudo chmod 644 /persist/host/secrets/initrd/ssh_host_ed25519_key.pub
```

- Do not reuse other keys for initrd unlock
- With systemd initrd, SSH login during early boot runs the password agent directly instead of dropping into a shell.

Unlock from another machine:

```zsh
ssh -tt -p 2222 root@192.168.4.200
```

## Console Rescue

If Baymax boots without an IPv4 address, log in at the console and set the usual LAN address temporarily:

```bash
sudo ip addr add 192.168.4.200/24 dev enp1s0
sudo ip route replace default via 192.168.4.1
```

Then verify from another machine:

```zsh
ssh me@192.168.4.200
```

## Secure Boot

Baymax uses Lanzaboote thin stubs. Do not delete `/boot/EFI/nixos`: the signed
entries in `/boot/EFI/Linux` can reference kernel and initrd payload files in
that directory. Treat `sbctl verify` output as a verification signal, not as a
cleanup list.

Before bootloader, Secure Boot, initrd, or ZFS-root changes, save an ESP backup
outside the ESP:

```zsh
sudo tar -C / -czf /persist/host/boot-backup-$(date +%Y%m%d-%H%M%S).tgz boot
```

Deploy risky boot changes with `boot` first, then reboot and verify before
running `switch`.

One-time key setup:

```bash
sudo sbctl create-keys
```

Build/install signed UKIs:

```bash
nix run nixpkgs#nixos-rebuild -- \
  boot \
  --flake .#baymax \
  --target-host me@192.168.4.200 \
  --build-host me@192.168.4.200 \
  --sudo \
  --ask-sudo-password
```

BIOS key import (Custom mode, authenticated variable):

- PK -> `PK.auth`
- KEK -> `KEK.auth`
- db -> `db.auth`

Verify:

```bash
sudo sbctl status
sudo sbctl verify
sudo bootctl status
```

## Cloudflare Tunnel

Baymax publishes its self-hosted apps through the Cloudflare tunnel named `baymax-apps`.

- The tunnel token lives in the secrets repo as `baymax-tunnel.age`.
- Baymax decrypts that secret as `age.secrets."baymax-tunnel"`.
- The host config wires it into `services.cloudflared.tunnels."baymax-apps".tokenFile`.

Relevant repo paths:

- `hosts/baymax/secrets.nix`
- `hosts/baymax/default.nix`

All app origins stay on Baymax loopback. Cloudflare is expected to forward to the local listeners, not to a LAN address.

## Published Routes

Current Cloudflare published application routes for `baymax-apps`:

| Hostname | Service URL | Notes |
| --- | --- | --- |
| `readeck.midsorbet.me` | `http://127.0.0.1:8000` | Readeck UI and extension path. Keep this out of Access if it should stay public. |
| `rss.midsorbet.me` | `http://127.0.0.1:8081` | Miniflux. Expected to stay behind Cloudflare Access. |
| `paperless.midsorbet.me` | `http://127.0.0.1:28981` | Paperless. Expected to stay behind Cloudflare Access. |
| `ntfy.midsorbet.me` | `http://127.0.0.1:8080` | ntfy. Expected to stay behind Cloudflare Access. |

The matching Baymax services are configured with these canonical hostnames in `hosts/baymax/default.nix`.

## Access Mapping

Intended Access posture:

- `readeck.midsorbet.me` is the narrow public exception.
- `rss.midsorbet.me`, `paperless.midsorbet.me`, and `ntfy.midsorbet.me` are the gated hostnames.
- If a wildcard Access app matches `*.midsorbet.me`, make sure `readeck.midsorbet.me` is explicitly excluded or otherwise not covered by that policy.

Useful symptoms:

- `302` to `midsorbet.cloudflareaccess.com` means the hostname is still matched by Access.
- `403` from Cloudflare on a gated hostname usually means the request did not satisfy the Access policy.
- `NXDOMAIN` means the published route or DNS record is missing, not that Baymax itself is down.

## Recovery

If the tunnel token rotates or the Cloudflare tunnel object gets deleted and recreated:

1. Update `baymax-tunnel.age` in the `nix-secrets` repo.
2. Refresh the pinned `secrets` input in this repo:

```zsh
nix flake update secrets --commit-lock-file
```

3. Redeploy Baymax so the new token reaches `/run/agenix/...` and the tunnel service restarts:

```zsh
nh os switch . \
  -H baymax \
  --target-host me@192.168.4.200 \
  --build-host me@192.168.4.200
```

After the config is pushed to `main`, Baymax can also build the reviewed GitHub
flake non-interactively through `nixos-upgrade.service`. This advances the boot
profile and reboots only inside the configured reboot window; it does not prove
the running system switched until `/run/current-system` matches the new profile.

```zsh
ssh me@192.168.4.200 '
  systemctl="$(readlink -f /run/current-system/sw/bin/systemctl)"
  sudo -n "$systemctl" start nixos-upgrade.service
'
ssh me@192.168.4.200 'systemctl status nixos-upgrade.service --no-pager -l'
ssh me@192.168.4.200 'readlink -f /nix/var/nix/profiles/system; readlink -f /run/current-system'
```

4. In Cloudflare, recreate the published application routes under `Networking -> Tunnels -> baymax-apps`.
5. Recheck the Access application scope so Readeck remains the public exception and the other app hostnames stay gated.

## Verification

Check Baymax-side service health:

```zsh
ssh me@192.168.4.200 'systemctl --failed --no-pager'
ssh me@192.168.4.200 'systemctl is-active cloudflared-tunnel-baymax-apps cloudflare-warp'
ssh me@192.168.4.200 'systemctl is-active immich-server immich-machine-learning paperless-web paperless-consumer paperless-scheduler paperless-task-queue readeck miniflux ntfy-sh'
```

Check the public hostnames. Readeck is intentionally public; the other app
hostnames should redirect to Cloudflare Access.

```zsh
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://readeck.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://rss.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://paperless.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://ntfy.midsorbet.me/
```

If macOS still reports stale DNS after the Cloudflare routes were restored:

```zsh
sudo dscacheutil -flushcache
```

```zsh
sudo killall -HUP mDNSResponder
```
