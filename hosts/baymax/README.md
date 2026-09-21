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

The existing `/persist/host/sbctl` bundle is required before installation.
Automatic key generation and enrollment are disabled. Restore the original PK,
KEK, db, and GUID; do not run `sbctl create-keys` or clear firmware keys during
recovery. The explicit `/etc/sbctl/sbctl.conf` keeps `sbctl` on these same paths.

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

Only if enrolled keys are genuinely missing, and after separate approval, import
the original authenticated variables in BIOS Custom mode:

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

The post-recovery targets are `archive/replica/baymax-persistSave-nvme` and
`archive/replica/baymax-persistHost-nvme`. Seed them from the final restored
encryption roots. Do not reuse the old raw incremental chains after
`zfs change-key -i`: an accepted stream and matching snapshot GUIDs did not prove
readability in the recovery experiment. Retain the old replicas and all recovery
datasets until final acceptance.

Inspect replication state without changing datasets:

```zsh
ssh me@192.168.4.200 'systemctl show sanoid.service syncoid-baymax-persist-save.service syncoid-baymax-persist-host.service -p Result -p ExecMainStatus -p ExecMainExitTimestamp --no-pager'
ssh me@192.168.4.200 'journalctl -u syncoid-baymax-persist-save.service -u syncoid-baymax-persist-host.service --since "7 days ago" --no-pager'
ssh me@192.168.4.200 'zfs list -t snapshot -o name,creation -s creation data/persistSave archive/replica/baymax-persistSave-nvme'
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
- Before the NVMe erase, the surviving `data` and `archive` pools were verified.
  The NVMe now has a fresh, verified `data` pool; the original archive and both
  data recovery copies remain intact. Their original key file is
  `/persist/host/secrets/zfs/data.key`, recovered from the host replica.
- `archive/replica/baymax-persistHost` was the daily copy at failure. Its
  `autosnap_2026-09-18_00:00:05_daily` snapshot contains the original host and
  initrd identities, data key, Secure Boot PKI, machine-id, and user password
  hash. An independently verified encrypted `host-state.zfs` is also on Mini
  and Hetzner. Restore it before install activation. Never put private contents
  into this repository. The host replica is its own encryption root: unlock
  `archive/replica/baymax-persistHost` with the original boot-disk (`rpool`)
  passphrase, not the parent `archive` pool. Its recovered
  `secrets/zfs/data.key` then unlocks `archive` and `data` without more prompts.
- `/home` had no ZFS replica. Borg archive
  `baymax-hetzner-2026-09-18T00:00:30` ran at 07:00:39-07:11:58 UTC on
  September 18. Its complete `home` tree was restored to encrypted `rpool/home`
  and authenticated against the archive on September 21. The newer retained
  workspace mirror was not replaced by this older home backup.
- Generic `/persist` was not backed up. This includes `/var/lib/nixos`,
  `/var/lib/systemd`, `/var/lib/cloudflare-warp`, and `/var/log/journal`. The host
  configuration pins the verified original numeric IDs before activation or
  tmpfiles can change ownership. WARP needs intentional
  re-registration; its previous state and the failure-time journal are not
  recovered.

Reviewed NVMe-only layout:

| Partition | Size | Use |
| --- | --- | --- |
| `disk-system-ESP` | 4 GiB | FAT EFI filesystem at `/boot` |
| `disk-system-rpool` | 480 GiB | Encrypted `rpool` |
| `disk-system-data` | Remaining 1,528,715,804,672 bytes | Encrypted `data` |

The sole Disko target is
`/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_20250501B1514`. The existing 2 TB Seagate
archive is mount-only and has no formatting declaration. USB remains temporary
rescue/install media and a native build workspace, not the installed boot
device. This replaces the earlier spare-SSD plan.

Recovery evidence and remaining gates:

- The Seagate recovery copy preserved all 59 snapshots and six source holds.
  A separately keyed restore matched all 410,617 current regular files and
  metadata; all 55 original historical snapshots were decrypted/read through.
- The independent Hetzner copy preserved the encrypted streams. Every payload
  passed complete-download checksums and native stream validation; an actual
  offsite cache restore matched 21,126 regular files. This was not a second
  full offsite restore of persisted-data history.
- The generated GPT procedure passed on a sparse RAM disk with the NVMe
  capacity of 2,048,408,248,320 bytes. Both physical GPTs and read-only guards
  were unchanged; the test loop and file were removed. Nix module assertions
  and the evaluated mount/signing contracts passed. This preliminary test did
  not establish a full system build, installed boot, or Secure Boot verification.
- The original RAM-backed rescue store could not hold the full build: the
  baseline dry-run needed 12.902 GiB of unpacked cached paths, before outputs
  and scratch, against a 7.7 GiB store. The Mini VM attempt stopped at a
  conservative free-space guard before building. The user then approved a
  direct Baymax build using the unused rescue-USB space.
- The Samsung USB now has a third, 237.379 GiB ext4 partition. An exact-capacity
  RAM-loop test preceded the change. Only the third MBR entry changed; the
  original ISO payload and both original partition entries were verified
  unchanged. The new filesystem passed `e2fsck`. The NVMe and Seagate stayed
  read-only. This was not a reboot test of the modified rescue USB.
- The rescue Nix store and database moved to USB with all 13,987 registered
  paths preserved and content-verified. A native build probe confirmed that
  build scratch also uses USB rather than RAM.
- The full native build of reviewed source `b862fc8` passed on 2026-09-21. Its
  13,563,230,504-byte closure is retained on USB. The expected derivation,
  kernel, initrd, boot specification, and original signing-key paths passed
  readback checks. Recursive content verification passed for all 1,841 closure
  paths. This does not establish installation, successful boot, active services,
  or Secure Boot acceptance.
- Read-only inspection verified and pinned these UID:GID pairs: `me`
  `1000:100`, `actual` `989:986`, `hister` `986:983`, `immich` `998:998`, and
  `readeck` `991:989`. PostgreSQL `71:71` and Paperless `315:315` already match
  their fixed IDs. The original host/initrd fingerprints, PKI file presence,
  and saved password-hash syntax were also checked without exposing secrets.
- The separately authorized NVMe erase and restore completed on 2026-09-21.
  The actual GPT and encrypted pools match the reviewed layout. All 58 child
  snapshot GUIDs, five original child holds, and two bookmarks with retained
  source snapshots were restored. Ten bookmark-only cursors remain recorded
  evidence, not restored objects. The original empty `data` root snapshot
  remains in the backups; it was not received over the fresh root.
- Full checksum and metadata comparisons found no changes across 410,617
  current data files or the 21 host-state files. All 55 original historical
  snapshots were decrypted/read through after a fresh data-root-only key reload.
  The restored host state also passed a fresh rpool-root-only key reload.
- Home verification covered all 515,336 entries, including 456,773 regular
  files and 17,015,673,476 bytes authenticated with Borg chunk IDs. Exact paths,
  numeric owners, types/modes, nanosecond mtimes, xattrs, symlink targets, and
  hardlink groups/counts matched. This is not a claim to restore ctime. Keep
  `rpool/home@nvme-home-restore-20260921` and its `baymax-nvme-recovery` hold.
- Both new pools passed physical-block scrubs with zero errors or repaired
  bytes. All 3,540 original archive object identities and the Seagate/USB
  partition tables remained unchanged. Intended dataset `readonly=off`
  properties were restored before exporting `data`, `rpool`, and `archive`.
  The NVMe, all three NVMe partitions, and the Seagate disk/partition are now
  block-read-only. Temporary credentials, decoded Borg metadata, helpers, and
  the private recovery terminal were removed or closed. Nothing was installed.

The final restore report is
`.git/agent-artifacts/baymax-nvme-restore-final-20260921.json`. The verification
bundle and parked-state log have matching SHA-256 copies on Mini and under
the USB workspace's `recovery-b862fc8/nvme-restore-evidence/` directory. Preserve
both copies and all earlier recovery evidence.

The native workspace is `/mnt/baymax-recovery-build`, mounted from ext4 UUID
`558bfd41-b13e-4535-b6ac-e7c570978f45` on Samsung USB serial
`0373026010000352`. Its `nix/store` and `nix/var/nix` directories are bound to
`/nix/store` and `/nix/var/nix`; build scratch uses its `build` directory. The
`recovery-b862fc8/system` link retains the built system, while `source` and
`input-roots/` retain the exact source and all 64 inputs. Keep the full closure
there, not in Mini's host store. Preserve this USB until installed recovery
passes acceptance.

These live bind mounts do not survive a rescue reboot. After any restart,
recheck disk identities and applicable read-only guards, mount the workspace
by UUID, and restore both bindings with the Nix daemon and socket stopped.
Keep the client store bind read-only; the daemon uses its writable namespace.
The current bindings and native builds were tested; a rescue reboot was not.

The first boot must use the separately built `recovery-held` generation,
retained at `recovery-b862fc8/firstboot-held-system`. Its isolated operational
overlay masks 66 system units and one user unit without changing repository
source. Native systemd resolved every generated mask to `/dev/null`; all 71
new closure paths passed content verification. Kernel, initrd, configured
kernel parameters, UID/GID assignments, essential mount/network/SSH units,
and fstab are unchanged. The full unit inventory, overlay, audit, and build
proof are under `recovery-b862fc8/firstboot-hold-evidence/`; the Mini report is
`.git/agent-artifacts/baymax-firstboot-hold-report-20260921.json`.

The holds cover application/database writers, backups and pruning, snapshot
and replication jobs, Syncthing, Hister, Hjem, WARP, Caddy, Cloudflared, ACME,
automatic upgrades, and the user VS Code fixer. Do not use boot-menu masks:
the complete list exceeds the editor and kernel limits, does not cover the
user manager, and Lanzaboote ignores edited options when Secure Boot is active.

These service holds do not make the filesystems immutable. Normal install/boot
activation still creates or normalizes persistent directories, links the
original machine-id, creates pinned users, decrypts agenix secrets, reconciles
`/etc`, and creates/replaces `/home/me/.ssh/id_github`. Required tmpfiles remains
enabled. Preserve the home recovery snapshot before these approved writes.
Release services only through a separately approved declarative generation;
use the normal generation only when every remaining hold may be released.
Do not bypass the held generation with runtime unmasking. No EFI image signing,
installation, activation, NVMe boot, or Secure Boot verification has run.

Recovery sequence: steps 1-4 are complete. Remaining installation and activation
require explicit approval; Secure Boot remains a separate gate. Do not rerun
Disko or the erase helpers for installation.

1. Confirm the retained reviewed build, original identities, and ownership
   records before the erase boundary. Keep both backups and the original NVMe
   read-only until that boundary is approved. Native-build evidence is in
   `.git/agent-artifacts/baymax-native-build-20260921.json`. Backup evidence
   remains under Mini's
   `/Users/me/.local/state/workspace-migration-20260918T205619Z/`; its latest
   report is `offsite-recovery-20260921T014217Z/verification/final-report.json`.
2. Partition only the named NVMe, then create fresh encrypted `rpool` and
   `data` roots. Preserve the archive and rescue media. Do not blindly run a
   complete provisioning script before restoring the original data key.
3. Receive the preserved data children and host-state snapshot into the fresh
   pools. Do not receive the original empty `data` root over an existing pool
   root. Load the original child keys, adopt the new roots, and verify all
   retained history and current metadata before permitting writes. Restore
   the intended mount, key-location, and read-only properties explicitly.
4. Restore `/home` from Borg without replacing newer retained workspace copies.
   Restore `/persist/host`, including the password hash and original Secure Boot
   PKI, before `nixos-install` activation. Pin observed UID/GID assignments
   before generating new NixOS allocation state or running tmpfiles.
5. Install only the retained `recovery-held` generation. On the actual first
   boot, verify every mask and confirm that held units never started. Keep
   restored-data writers, backup/prune jobs, Syncthing, Hister, WARP, and
   dependent Caddy stopped through verification. Recreate WARP registration
   intentionally in an approved release stage; verify its private route before
   enabling Caddy. Keep Mini mirroring/private search paused.
6. Verify NVMe-only boot and original SSH identities. After separate approval,
   re-enable Secure Boot with the existing enrolled keys and verify signed
   startup. Only then accept the restored services, seed fresh active replicas,
   and resume mirroring/search. Do not retire recovery copies before acceptance.

Keep the failed SSD and all existing recovery copies. Never initialize the
failed SSD. If it becomes readable, image it before further recovery work.

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
