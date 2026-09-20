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

Baymax publishes selected self-hosted apps through the Cloudflare tunnel named `baymax-apps`.

- The tunnel token lives in the secrets repo as `baymax-tunnel.age`.
- Baymax decrypts that secret as `age.secrets."baymax-tunnel"`.
- The host config wires it into `services.cloudflared.tunnels."baymax-apps".tokenFile`.

Relevant repo paths:

- `hosts/baymax/secrets.nix`
- `hosts/baymax/default.nix`

Cloudflare forwards to Baymax loopback listeners. OMP and Herdr are intentionally not part of this standing public Cloudflare route set.

## Published Routes

Current Cloudflare published application routes for `baymax-apps`:

| Hostname | Service URL | Notes |
| --- | --- | --- |
| `readeck.midsorbet.me` | `http://127.0.0.1:8000` | Readeck UI and extension path. Keep this out of Access if it should stay public. |
| `rss.midsorbet.me` | `http://127.0.0.1:8081` | Miniflux. Expected to stay behind Cloudflare Access. |
| `paperless.midsorbet.me` | `http://127.0.0.1:28981` | Paperless. Expected to stay behind Cloudflare Access. |
| `ntfy.midsorbet.me` | `http://127.0.0.1:8080` | ntfy. Expected to stay behind Cloudflare Access. |
| `photos.midsorbet.me` | `http://127.0.0.1:2283` | Immich. Expected to stay behind Cloudflare Access. |
| `budget.midsorbet.me` | `http://127.0.0.1:5006` | Actual Budget. A separate Access app requires the configured identity and Gateway device posture. |

The matching Baymax services are configured with these canonical hostnames in `hosts/baymax/default.nix`.

## Access Mapping

Intended Access posture:

- `readeck.midsorbet.me` is the narrow public exception.
- `rss.midsorbet.me`, `paperless.midsorbet.me`, `photos.midsorbet.me`, `ntfy.midsorbet.me`, and `budget.midsorbet.me` are the gated hostnames.
- `lab.midsorbet.me` should not have standing DNS records, tunnel ingress rules, or Access app entries.
- `omp.midsorbet.me` belongs to the separate, Mini-hosted `omp-collab` Tunnel and Access app. Its DNS and Access entries are standing, but the relay and tunnel run only on demand; never add it to `baymax-apps`.
- `herdr.midsorbet.me` is a proxied CNAME to the dedicated Mini connector for
  Cloudflare Tunnel `bd9f42c3-efc9-41c0-92f2-dba61e205ffd`; never add it to
  `baymax-apps`. The existing `private-herdr` Access policy allows
  `l.khadka@outlook.com` and inherits the Herdr SSH application's eight-hour
  session; leave the policy duration unset. Mini separately controls its eight-hour
  default, twelve-hour maximum lease with `herdr-relay start --ttl 8h`,
  `herdr-relay status`, and `herdr-relay stop`; starting it again never silently
  extends an active lease. Clients use the Delcatty SSH key with
  `ProxyCommand cloudflared access ssh --hostname %h`, not WARP.
- If a wildcard Access app matches `*.midsorbet.me`, make sure `readeck.midsorbet.me` is explicitly excluded or otherwise not covered by that policy.

Useful symptoms:

- `302` to `midsorbet.cloudflareaccess.com` means the hostname is still matched by Access.
- `403` from Cloudflare on a gated hostname usually means the request did not satisfy the Access policy.
- `NXDOMAIN` means the published route or DNS record is missing, not that Baymax itself is down.
- `ERR_CONNECTION_REFUSED` for `readeck`, `photos`, `budget`, `hister`, or `atuin` on the home LAN means split-horizon DNS reached `192.168.4.200`, but Caddy is not listening. Check `systemctl status caddy` and the port 443 listeners on Baymax before investigating Cloudflare.
- A Caddy boot failure that mentions `100.96.0.3:443` means the WARP address was not ready. The managed Caddy pre-start gate must wait for that address before Caddy binds its listeners.

## Local HTTPS Security Boundaries

- Use exact split-DNS records, Caddy virtual hosts, and certificates. Never use a
  wildcard local rewrite, wildcard certificate, or catch-all proxy route.
- Keep each Unbound local zone authoritative for its exact application name so
  public `AAAA`, `HTTPS`, `SVCB`, or `CNAME` answers cannot race the local `A`
  answer. ACME propagation checks must use an explicit public resolver.
- Bind Unbound only to the intended LAN addresses, allow TCP and UDP 53 only
  from the main LAN, deny recursion from WARP, guest, container, and unintended
  interfaces, and leave query logging off outside a bounded diagnosis.
- Bind application Caddy listeners only to the reviewed LAN and WARP addresses;
  never use `0.0.0.0` or an unreviewed IPv6/container interface. Keep Caddy's
  admin endpoint disabled or loopback-only.
- Strip client-supplied Cloudflare identity and forwarding headers before a LAN
  request reaches an application. A local route must not inherit edge identity.
- Keep the DNS-01 token in agenix, readable only by the ACME unit and limited to
  the permissions and zone that lego requires. Keep certificate private keys
  readable only by ACME and Caddy. Review current Cloudflare issuers before
  changing CAA and monitor Certificate Transparency for unexpected issuance.
- Treat main-LAN membership as authorization to reach local login surfaces;
  untrusted and IoT devices stay on the eero guest network.
- For Cloudflare control-plane work, use the configured Cloudflare MCP connector
  first and inspect its current schema. If discovery, authentication, schema
  retrieval, or a correctly formed call fails, stop rather than falling back to
  the web UI, browser automation, direct REST credentials, or another OAuth
  flow. Mutations require explicit authorization and have zero automatic retries.
- Keep local application fallbacks out of the default/away WARP profile. Apply
  them only through the higher-priority home Managed Network profile, preserve
  Gateway filtering for non-local names, and test DNS selection separately from
  reachability on every supported client.
- Readeck is intentionally public and relies on its own login. Treat a future
  exploitable upstream advisory as urgent: upgrade or backport promptly, or
  disable public ingress until fixed.

## Actual Budget

Actual listens only on Baymax loopback port `5006`. Its server and user files live
under `/persist/save/actual` with `0700` ownership by the static `actual` service
account.

`budget.midsorbet.me` has its own Cloudflare Access application. The
`private-actual` allow policy copies the existing private-lab identity selector,
requires the `Gateway` device-posture rule, and uses a `720h` session duration.
A client without the required posture receives a Cloudflare Access `403`; this
does not indicate an Actual origin failure.

Treat the imported YNAB data as historical reference, not authoritative current
account state or budget targets. The manually verified Actual budget is the live
baseline.
Before each Borg run, `actual-backup.service` stops Actual briefly, snapshots the
`data/persistSave` ZFS dataset, restarts Actual, writes the validated archive to
`/persist/save/actual-backups/actual-server.tar.zst`, and destroys the temporary
snapshot. Verify the live backup path with:

```zsh
ssh -t me@192.168.4.200 'sudo systemctl start actual-backup.service'
ssh me@192.168.4.200 'systemctl show actual-backup.service --property=Result,ExecMainStatus,ExecMainStartTimestamp,ExecMainExitTimestamp'
ssh -t me@192.168.4.200 'sudo tar --list --zstd --file /persist/save/actual-backups/actual-server.tar.zst >/dev/null'
```

Actual's end-to-end encryption password is retained only in the password manager.
Never copy it into this repository, the vault, Reminders, Nix configuration, or
backup archives. This deliberately leaves one custodian: losing password-manager
access makes encrypted Actual data and encrypted backup history unrecoverable.

## ZFS Replication and Disk Health

Sanoid takes the configured hourly source snapshots. The daily Syncoid transfers
use `--no-stream --no-sync-snap --use-hold --create-bookmark`. `--no-stream`
sends only the newest available snapshot per run and ensures that bookmark-based
recovery in the locked Syncoid 2.3.0 reaches its hold and bookmark lifecycle.
After a completed transfer, Syncoid holds the newest snapshot on both sides,
releases its previous holds, and creates a source bookmark as the durable
incremental base. While each unit runs, the module delegates only
`bookmark,hold,release,send` on its source and
`create,hold,mount,receive,release,rollback` on its target.
Both replication units and Sanoid publish failures to the local ntfy system topic;
smartd health-warning events use the same publisher while retaining the ntfy
publisher credentials in the smartd service environment.

Inspect replication state without changing datasets:

```zsh
ssh me@192.168.4.200 'systemctl show sanoid.service syncoid-baymax-persist-save.service syncoid-baymax-persist-host.service -p Result -p ExecMainStatus -p ExecMainExitTimestamp --no-pager'
ssh me@192.168.4.200 'journalctl -u syncoid-baymax-persist-save.service -u syncoid-baymax-persist-host.service --since "7 days ago" --no-pager'
ssh me@192.168.4.200 'zfs list -t snapshot -o name,creation -s creation data/persistSave archive/replica/baymax-persistSave'
ssh me@192.168.4.200 'zfs list -t bookmark -o name,creation -s creation data/persistSave'
```

## Atuin Security and Recovery

- Keep Atuin bound to loopback behind its reviewed split-horizon HTTPS route.
  Home DNS resolves to Baymax; away clients use the private WARP route.
- Keep the account password and encryption key only in agenix and the user's
  password manager. Do not copy their values into this repository or vault.
- Do not use Atuin's importer directly on legacy shell histories: the importer
  bypasses runtime history and secret filters. Sanitize any future import first
  and retain the original history only as protected rollback evidence.

## Boot Disk Failure (2026-09)

Hardware: Beelink Mini S13 Pro (firmware `AZW MINI S`, BIOS `MINISF005`,
Alder Lake-N). Two M.2 2280 slots: the left `SATA3/NVMe` combo slot held the
bundled boot SSD; the right `PCIe 3.0 x1` slot is NVMe-only and holds the 2 TB
SPCC data NVMe.

On 2026-09-19 at about 03:31 UTC the boot SSD
(`ata-512GB_SSD_MQ23W96605594`; label AZW `S302F512G`, M.2 2280 SATA, B+M key)
dropped off the bus while the system was running. SSH accepted TCP but never
sent a banner, ping kept answering, and the foreground Hister query could not
be interrupted. On the next boot the firmware listed SATA ports 0-2 as Empty
and offered no boot entry. Secure Boot was still enabled in Custom mode with
the existing keys.

Evidence from the NixOS live USB (kernels 6.18.52 and 7.2.6):

```text
ahci 0000:00:17.0: 1/1 ports implemented (port mask 0x2)
ata2: link is slow to respond, please be patient (ready=0)
ata2: found unknown device (class 0)
ata2: SATA link down (SStatus 0 SControl 300)
```

The link completes OOB negotiation, but the drive never sends its signature
FIS. Link power policy, controller reprobe, forced 1.5 Gbps, reseating, and a
second kernel did not change the result. The firmware detects the 2 TB NVMe in
the combo slot, so that slot has power and PCIe. Deployed source `5e89bb0`
evaluates to the same kernel, parameters, initrd and kernel modules, EFI, and
Lanzaboote settings as pre-migration `cbe2c66`; `disk-config.nix` and
`flake.lock` did not change. Assessment: SSD failure is the most likely cause;
a slot SATA-lane fault remains possible. Evidence is retained on Mini under
`/Users/me/.local/state/workspace-migration-20260918T205619Z/verification/`
(`live-usb-storage-diagnosis.json`, `sata-isolation-20260919.json`,
`alternate-kernel-test.json`).

Recovery dependencies:

- `rpool` (`/`, `/nix`, `/home`, `/persist`, `/persist/host`) lived only on the
  failed SSD.
- `data` and `archive` are `ONLINE` but locked. Their key file
  `/persist/host/secrets/zfs/data.key` was on the SSD. The passphrase is known
  and can be supplied with `zfs load-key -L prompt <pool>`.
- `archive/replica/baymax-persistHost` is the configured daily Syncoid copy of
  `/persist/host`: agenix host key, `data.key`, `sbctl` PKI, initrd host key,
  and `machine-id`. Verify its newest snapshot at import. Recovering it
  restores every Baymax-only secret, including the Hetzner Borg credentials.
- `/home` had no snapshot or replica. Restore it from the Hetzner Borg repo
  (`repokey-blake2`; passphrase known). Loss is limited to changes since the
  last daily run.
- Not backed up: `/var/lib/cloudflare-warp`, `/var/lib/nixos`,
  `/var/log/journal`, and the failure-time journal.

Rebuild plan:

1. From the live USB: `zpool import -f -N -o readonly=on archive` and `data`,
   `zfs load-key -L prompt` for each, check `zpool status`, mount the
   `baymax-persistHost` replica, confirm the recovered host public key matches
   the `baymax` recipient in the secrets repo, copy `/persist/host` off the
   host, confirm `borg list` reaches Hetzner, then export both pools.
2. Boot disk: use an NVMe 2280 drive in the combo slot. It works whether the
   SSD or the slot's SATA lanes failed. Change the `system` device in
   `disk-config.nix` to the new `nvme-...` ID; keep the ESP and `rpool` layout.
3. Install: partition only the new disk (filter the disko config so `data` and
   `archive` are untouched; keep the Seagate unplugged), restore
   `/persist/host` before the first `nixos-install`, install `5e89bb0` with the
   device change, restore `/home` from Borg, then re-enable Secure Boot with the
   existing keys.
4. Keep the failed SSD. If an M.2 SATA USB enclosure reads it, image it first,
   then import `rpool` read-only to recover the last day of `/home` and the
   journal. Never initialize or format it.

Open fixes this incident calls for:

- Encrypt the Hetzner Borg secrets, the Baymax host SSH private key,
  `data.key`, and the `sbctl` bundle to the `mini` recipient as well, so any
  machine with Mini's key can rebuild Baymax without the replica.
- Alert from outside Baymax: a Mini-side reachability check that publishes to
  a channel Baymax does not host. `ntfy-failure@` cannot report the host's own
  death.
- Out-of-band console (JetKVM class) on Baymax.
- A second x86 box as ZFS replication target, second Syncthing receiver,
  `x86_64-linux` remote builder, and cold standby; the N100 becomes the small
  always-on standby. The purchase decision lives in the vault purchases note.

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
ssh me@192.168.4.200 'systemctl is-active caddy cloudflared-tunnel-baymax-apps cloudflare-warp avahi-daemon'
ssh me@192.168.4.200 'getent hosts mini-me.local'
ssh me@192.168.4.200 'systemctl is-active actual immich-server immich-machine-learning paperless-web paperless-consumer paperless-scheduler paperless-task-queue readeck miniflux ntfy-sh'
```

Check the published hostnames. Readeck is intentionally public; the other app
hostnames should return a Cloudflare Access redirect or policy denial.

```zsh
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://readeck.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://rss.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://paperless.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://ntfy.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://photos.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://budget.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://hister.midsorbet.me/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://atuin.midsorbet.me/
```

If macOS still reports stale DNS after the Cloudflare routes were restored:

```zsh
sudo dscacheutil -flushcache
```

```zsh
sudo killall -HUP mDNSResponder
```
