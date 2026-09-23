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
ssh -tt -p 2222 root@192.168.4.31
```

## Console Rescue

If Baymax boots without an IPv4 address, log in at the console and set the usual LAN address temporarily:

```bash
sudo ip addr add 192.168.4.31/24 dev enp1s0
sudo ip route replace default via 192.168.4.1
```

Then verify from another machine:

```zsh
ssh me@192.168.4.31
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
  --target-host me@192.168.4.31 \
  --build-host me@192.168.4.31 \
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
- `ERR_CONNECTION_REFUSED` for `readeck`, `photos`, `budget`, `hister`, or `atuin` on the home LAN means split-horizon DNS reached `192.168.4.31`, but Caddy is not listening. Check `systemctl status caddy` and the port 443 listeners on Baymax before investigating Cloudflare.
- A Caddy boot failure that mentions its configured WARP listener on port 443 means that address was not ready. The managed Caddy pre-start gate must wait for the address in `local-https.nix` before Caddy binds its listeners.

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
ssh -t me@192.168.4.31 'sudo systemctl start actual-backup.service'
ssh me@192.168.4.31 'systemctl show actual-backup.service --property=Result,ExecMainStatus,ExecMainStartTimestamp,ExecMainExitTimestamp'
ssh -t me@192.168.4.31 'sudo tar --list --zstd --file /persist/save/actual-backups/actual-server.tar.zst >/dev/null'
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
ssh me@192.168.4.31 'systemctl show sanoid.service syncoid-baymax-persist-save.service syncoid-baymax-persist-host.service -p Result -p ExecMainStatus -p ExecMainExitTimestamp --no-pager'
ssh me@192.168.4.31 'journalctl -u syncoid-baymax-persist-save.service -u syncoid-baymax-persist-host.service --since "7 days ago" --no-pager'
ssh me@192.168.4.31 'zfs list -t snapshot -o name,creation -s creation data/persistSave archive/replica/baymax-persistSave-nvme'
ssh me@192.168.4.31 'zfs list -t bookmark -o name,creation -s creation data/persistSave'
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
  At that restore boundary, the NVMe, all three NVMe partitions, and the Seagate
  disk/partition were block-read-only. Temporary credentials, decoded Borg
  metadata, helpers, and the private recovery terminal were removed or closed.
  Nothing had yet been installed.
- Separately approved installation and bootstrap activation completed on
  2026-09-22 UTC. Only generation 1 of the retained `recovery-held` system was
  installed. Recursive content verification of the copied target closure passed.
  The signed loader copies and thin UKI passed independent signature checks;
  the signing certificate matches an already enrolled firmware `db` certificate.
  Signed kernel/initrd hashes, the exact held kernel command line, the base
  initrd, and the embedded original initrd SSH identity all matched.
- All 67 installed unit masks passed offline target-root checks. All 21 original
  host-state files still match the recovered snapshot byte-for-byte, including
  the original SSH identities, data key, password hash, and signing PKI. Pinned
  UID:GID pairs and the activated login password hash passed readback. The home
  recovery hold and blank root snapshot remain present.
- At installation, firmware entry `Boot0000`, labelled `NixOS Baymax`, selected
  the NVMe ESP and `\EFI\systemd\systemd-bootx64.efi`. `BootNext` was `0000`;
  `BootOrder` was `0000,0001,0002`. Both original boot entries were unchanged.
  Secure Boot remained disabled. `SecureBoot`, `SetupMode`, `PK`, `KEK`, and
  `db` were unchanged; `dbx` remained absent.
- After installation verification, `data` and `rpool` were cleanly exported with
  no remaining target mounts. The NVMe and Seagate disk/partition guards were
  block-read-only, and all three partition tables were unchanged. The archive
  stayed exported. Actual NVMe boot had not yet been tested at that boundary.

The final restore report is
`.git/agent-artifacts/baymax-nvme-restore-final-20260921.json`. The verification
bundle and parked-state log have matching SHA-256 copies on Mini and under
the USB workspace's `recovery-b862fc8/nvme-restore-evidence/` directory. Preserve
both copies and all earlier recovery evidence.

The installation report is
`.git/agent-artifacts/baymax-nvme-installation-20260921.json`. Matching SHA-256
verification bundles are retained on Mini and at
`recovery-b862fc8/installation-verification.tar.gz` on the USB. The first installer
attempt stopped before copying because positional `script` arguments discarded
empty option values. Explicit `script --command` quoting fixed that failure;
the failed attempt and successful retry remain in the evidence bundle.

The preserved native workspace is on ext4 UUID
`558bfd41-b13e-4535-b6ac-e7c570978f45`, Samsung USB serial `0373026010000352`.
During rescue it is mounted at `/mnt/baymax-recovery-build`; its `nix/store` and
`nix/var/nix` directories are bound to `/nix/store` and `/nix/var/nix`, and build
scratch uses its `build` directory. The `recovery-b862fc8/system` link retains
the reviewed normal system. `firstboot-held-system`, `source`, and `input-roots/`
retain the held system, exact source, and all 64 inputs. Keep the closures there,
not in Mini's host store. Preserve this USB until installed recovery passes
acceptance.

Only an approved return to the rescue environment may reuse that workspace.
In that environment, recheck disk identities and applicable read-only guards,
mount the workspace by UUID, and restore both bindings with the Nix daemon and
socket stopped. Keep the client store bind read-only; the daemon uses its writable
namespace. Those rescue bindings and native builds were tested before installation.

The first NVMe boot used the separately built `recovery-held` generation,
retained on the disconnected USB at `recovery-b862fc8/firstboot-held-system`.
Its isolated operational overlay masks 66 system units and one user unit without
changing repository source. Native systemd resolved every generated mask to
`/dev/null`; all 71
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
Do not bypass the held generation with runtime unmasking. Installation,
bootstrap activation, offline EFI checks, NVMe boot, and live hold checks have
passed. The corrected held generation has also passed startup acceptance.
Secure Boot startup passed with the original enrolled keys. This is the held
baseline; the separately approved local-service releases are recorded below.

### First NVMe boot and ownership correction

Baymax first booted the installed held generation from the NVMe with the Seagate
and Samsung rescue USB disconnected. Keep the Samsung disconnected. The archive
has writable normal fstab mounts and a tmpfiles entry for `/archive/immich`;
reconnect the Seagate only through the guarded service-restoration stage below.

The recovery DHCP address changed from `192.168.4.29` on the first NVMe boot to
`192.168.4.31` after the ownership correction, then to `192.168.4.24` for the
verified Secure Boot startup. The user supplied `192.168.4.27` after generation
4 booted, and generation 6 later received `.30`. Generation 7 uses the Ethernet
MAC as the DHCPv4 client identifier in both initrd and normal boot; its real boot
received `.31` in both stages. Generation 9 makes `.31` the permanent LAN service
address. Configure the eero reservation and secondary custom DNS endpoint to
`.31`; do not rewrite service or Cloudflare addresses to follow another lease.
Use `.31` or the stable ULA for administration. The original stage-two SSH
identity is unchanged; keep its existing host-key pin:

```zsh
ssh -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.4.31 \
  -o CheckHostIP=no me@192.168.4.31
```

The real boot verified the held UKI and kernel, root rollback, all eight required
mounts, and healthy `rpool` and `data` pools. All 63 retained recovery-object
identities and creation records match the preboot inventory. All 21 original
host-state files still match their recovered snapshot. Original SSH identities,
machine-id, password hash, and pinned UID:GID pairs passed readback. All 66 system
masks and the one user mask are inactive, with no invocation or start record.

On the first NVMe boot, `BootCurrent` was `0000`, and `BootNext` was consumed.
Firmware also exposed `Boot0003` as a fallback entry on the same NVMe ESP. All
five installation-artifact hashes and the original Secure Boot variable hashes
matched at that boundary. Secure Boot remained disabled.

`zfs-import-archive.service` fails after waiting about 62 seconds because the
archive disk is intentionally absent. This is the only failed unit. Do not
reconnect the archive or import it to remove this expected failure.

The first boot exposed a tmpfiles ownership problem. `/persist/save` was
`1000:100` with mode `0755`. Tmpfiles refused unsafe transitions through this
user-owned parent into the correctly owned Actual, Immich, Paperless, and
PostgreSQL directories. The unit reported `Result=success`, but
`ExecMainStatus=73`; the upstream unit accepts exit statuses 65 and 73. That
reported success did not prove that directory setup completed.

The source correction adds `/persist/save` to the existing `root:root` `0755`
tmpfiles group. A root-run RAM fixture reproduced exit 73 with the old ownership.
Adding only the parent rule produced exit 0 and created the missing child while
preserving existing child ownership and file bytes, mode, size, and mtime. The
fixture was removed without changing the live directory. The later approved
boot applied the declarative parent rule. No recursive ownership repair was used.

The corrected held generation was built and reviewed natively, then installed
and booted as generation 2 under separate explicit approval:

```text
/nix/store/2qhrz8dz3iyybm1gzg89vv8xrjfpa0m5-nixos-system-baymax-recovery-held-26.11.20260919.20b1ddd
```

Its GC root is
`/home/me/.local/state/nix/gcroots/baymax-owner-repair-20260921/system`. All 64
source/input store paths are retained under the adjacent `inputs/` directory.
The compiled tmpfiles difference is exactly the new parent rule. All 67 masks,
the kernel, initrd, kernel parameters, and fstab are preserved. The activation
script differs only in the system and generated `/etc` store references. Signing
still requires the original PKI, with automatic key generation and enrollment
disabled. The running system and system profile now both select this generation.
The original `52rglinpl5y5pi35b00fap9kdhkq0y5c-…` system remains generation 1.

First-boot proof is recorded in
`.git/agent-artifacts/baymax-firstboot-verification-20260921.json`. The correction
report is `.git/agent-artifacts/baymax-owner-repair-20260921.json`; the retained
build expression and audit are beside it. The evidence bundle is
`.git/agent-artifacts/baymax-firstboot-verification-20260921.tar.gz`.

The approved boot-only deployment preserved a root-only ESP backup at
`/persist/host/boot-backup-owner-repair-20260922T025206Z-wP6V8J.tgz`. Both loader
copies and both held UKIs passed independent signature verification against the
original enrolled certificate. Signed payload hashes, the base initrd, and the
embedded original initrd SSH identity passed verification before the reboot.
Generation 2 was the default boot entry; generation 1 remained available.

The real firmware reboot selected generation 2. Boot ID
`b1094c9e-c0b5-4560-ad68-8e91934fdab9` differs from the first boot. Tmpfiles
actually ran and exited **0**, with no unsafe-path messages. `/persist/save` is
now `0:0` with mode `0755`; service-owned children have the expected owners and
modes. Root rollback completed again. All eight mounts, both healthy pools, all
63 recovery objects, the home recovery hold, all 21 original host-state files,
original identities, and all seven pinned UID:GID pairs passed the postboot
checks. All 67 live masks remain inactive with no invocation or journal record.

The signed boot artifacts passed verification again after the corrected boot.
At that boundary, original Secure Boot enrollment and mode variables were
unchanged, and Secure Boot was disabled. The missing archive was the only failed
unit. Both external disks remained disconnected. No restored service, mirror,
or private-search consumer was released.

The earlier corrected-boot acceptance report is
`.git/agent-artifacts/baymax-owner-deployment-20260921.json`. The evidence bundle
`.git/agent-artifacts/baymax-owner-deployment-verification-20260921.tar.gz` has a
matching SHA-256 copy under the native build workspace
`/home/me/.local/state/nix/gcroots/baymax-owner-repair-20260921/evidence/`.
Temporary verification scripts and tool roots were removed. Private administrative
terminals were closed, and sudo credentials were invalidated. Retain the builds,
source roots, ESP backup, and all earlier recovery copies.

NVMe startup and Secure Boot acceptance are complete. The user approved staged
service restoration on September 22; full service, routing, privacy, and
active-consumer acceptance remain open. Keep mirroring and private search paused.
Do not rerun Disko or the erase or installation helpers. Steps 1–4 below record
the completed restore sequence, not instructions to repeat it.

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
5. Corrected `recovery-held` generation 2 passed real startup acceptance with
   tmpfiles exiting 0, matching storage/identities, and all 67 holds inactive.
   This is the baseline for the approved staged releases below. Retain every
   remaining hold. Restore WARP registration intentionally and verify the LAN
   address and private route before enabling Caddy. Keep Mini mirroring and
   private search paused until their acceptance gates pass.
6. Generation 2 has passed signed startup with Secure Boot enforcement enabled
   and the original enrolled keys unchanged. Only a separately approved
   declarative generation may release restored services. Accept services and
   privacy/routing before seeding active replicas or resuming mirroring/search.
   Do not retire recovery copies before acceptance.

The Secure Boot preflight on `2026-09-22T03:54:03Z` confirmed that the four EFI
images, signed kernel/initrd payloads, and original firmware keys still match
the accepted generation 2 proof. Both pools were healthy, tmpfiles exited 0, and
all 67 holds remained masked and inactive. A fresh, verified ESP backup is
retained only on Baymax at
`/persist/host/boot-backup-secureboot-20260922T035400Z-7c5n20.tgz`, owned by
`0:0` with mode `0600`. Do not copy this sensitive archive to Mini.

Baymax accepted the firmware-setup reboot, then returned at `192.168.4.24` with
new boot ID `b69d9eb9-c53c-444a-85bd-603e570d8a11`. Firmware reports
`SecureBoot=1` and `SetupMode=0`; `sbctl` reports Enabled, and `bootctl` reports
`enabled (user)`. Of the five monitored Secure Boot variables, only the enable
byte changed. Original PK, KEK, db, SetupMode, and signing-certificate identities
are unchanged; dbx remains absent. No key replacement or enrollment was needed.

The firmware selected the same default generation 2 UKI. All four EFI images
passed independent signature verification again and remain byte-identical to
the accepted preflight. Signed kernel/initrd hashes, the base initrd, and the
embedded original initrd SSH identity passed readback. Generation 1 is retained.
Root rollback completed. Both pools remain ONLINE with zero errors, all eight
mounts match, all 63 recovery-object records and the home recovery hold remain
intact, and all 21 original host-state files still match their recovered snapshot.
The machine-id, password hash, SSH identities, and seven pinned UID:GID/group
pairs passed verification. Tmpfiles ran and exited 0, with no unsafe transitions.

At the generation 2 acceptance boundary, all 66 system holds and the user hold
were masked and inactive, with no held-unit invocation or start record. The
absent archive was the only failed unit; both external disks were disconnected.
No service, mirror, or private-search consumer had been released at that point.

The Secure Boot startup acceptance report is
`.git/agent-artifacts/baymax-secureboot-verification-20260921.json`. The frozen
bundle `.git/agent-artifacts/baymax-secureboot-verification-20260921.tar.gz` has
a matching SHA-256 copy in the retained native build workspace
`/home/me/.local/state/nix/gcroots/baymax-owner-repair-20260921/evidence/`.
Raw native evidence is in
`/home/me/.local/state/nix/gcroots/baymax-owner-repair-20260921/secureboot-proof/`.
The earlier
`.git/agent-artifacts/baymax-secureboot-handoff-20260921.json` records the
pre-enablement boundary, not the current status. Temporary verification helpers
were removed, the one-shot privileged session closed, and sudo credentials were
invalidated on both hosts. The held system, all 64 source/input roots, ESP backups,
and earlier recovery copies remain retained.

### Approved service restoration (2026-09-22)

The user approved staged restoration, not a switch to the unmasked normal
generation. Before releasing writers, five
`service-restoration-prewrite-20260922` snapshots of `rpool/home`,
`rpool/persist`, `rpool/persistHost`, `data/persistSave`, and `data/cache` received
the `baymax-service-restoration` hold. Keep those holds and every older recovery
copy. Their identities are in
`.git/agent-artifacts/baymax-prewrite-protection-20260922.json`.

The first local-service generation was activated and tested. PostgreSQL, Actual,
Atuin, Miniflux, Paperless, Readeck, and the managed-network beacon passed their
local acceptance checks. A read-only PostgreSQL transaction confirmed version
17.11 and `/persist/save/postgresql/17`. The application origins remain on
loopback. WARP runs but has no recovered registration; this is not working
private routing. Caddy, Cloudflared, ACME, Immich, Hjem, the auth broker,
Syncthing, Hister/importer, backups, pruning, and automatic upgrades remain held.
The staged generation retains 54 system masks and one user mask.

The router remains on ISP DNS. Before the later DHCP address change, direct
IPv4/IPv6 UDP/TCP queries passed against Mini and Baymax.
Isolated per-unit tests blocked each primary resolver in turn
and verified local and upstream resolution through the other resolver; the host
resolver file stayed unchanged. Mini now starts loopback Unbound immediately,
waits for Ethernet before starting its LAN listener, and starts the VZ builder
after loopback DNS owns its sockets. The VM and Rosetta remained functional.
Cloudflare managed-network and Home-profile fallback addresses were changed
from the former address to `.24`, then read back under the narrowly approved
idempotent retry exception. Generation 9 later changed the Home LAN managed-
network TLS endpoint to `192.168.4.31:9443` through the native API. Readback
retained the existing SHA-256 pin, and the live beacon certificate fingerprint
matched it. A subsequent explicitly approved Home-profile update replaced
`.24` with `.31` in the existing Photos, Readeck, and Budget fallbacks and
added exact Hister and Atuin fallbacks with the same four redundant LAN
resolvers.

Archive reconnection exposed a boot-time driver prerequisite: with the Seagate
absent at startup, `usb_storage` was not loaded before
`security.lockKernelModules` set `kernel.modules_disabled=1`. USB enumeration
succeeded, but no disk device appeared. `boot.kernelModules` now preloads
`usb_storage` and `sd_mod`; `initrd.availableKernelModules` alone is not a
preload guarantee. Keep the security lock and the Seagate UAS quirk enabled.
The fix requires a reboot, not a late `modprobe` or a weaker security policy.

Both host builds passed for the driver fix. Mini rebuilt to its already-active
system. Baymax generation 4 was installed and passed the approved reboot with
the Seagate disconnected. Its kernel, initrd, kernel parameters, numeric
identities, PostgreSQL, and release set are unchanged. Its UKI and both loaders
passed verification with the recovered db certificate; generations 1–3 stayed
byte-identical. Active, booted, and selected system paths now all match:

```text
/nix/store/6058flmz3976278lfl7cq2kfg2wzcq95-nixos-system-baymax-recovery-local-26.11.20260919.20b1ddd
```

Before reconnection, live checks verified both preloaded drivers, the module
lock, Secure Boot with the original owner GUID, all 54 system holds and the
user hold, healthy pools, retained prewrite holds, and the WWN-specific
block-read-only rule. There were no failed units. Fresh Seagate hotplug then
produced the expected disk and partition with both kernel read-only flags set.
Serial, WWN, sizes, original GPT, and all four labels matched the retained
pool GUID `2793237780643487490`.

The archive imported ONLINE with `readonly=on`, `cachefile=none`, no mounts,
and private alternate root `/run/baymax-archive-readonly-20260922`. All 3,540
original archive object identities matched exactly. After that identity check,
the original key loaded from its recovered file and only `archive/media` mounted
in the private read-only location. An isolated read-only namespace let UID 998
check all 11,095 original and 31,650 derived paths referenced by Immich. No path
was missing, unreadable, or outside `/archive/immich`. This proves presence and
read access, not complete file-content checksums. No private filenames were
exported, and the production mount, replicas, and Immich remained held.

The private media mount was then unmounted, the archive key unloaded, and the
pool exported without force. The connected Seagate disk and partition retain
their kernel read-only flags. All five original prewrite snapshot identities
and holds passed the closeout check; `rpool` and `data` were healthy, with no
failed system units. The 54 system holds and one user hold remain in force.
Completed diagnostic helpers and compiler caches were removed. The temporary
root session closed and sudo credentials were invalidated on both hosts; the
user-owned Herdr tab remains open. All recovery copies, builds, overlays, and
evidence remain retained. The live acceptance report is
`.git/agent-artifacts/baymax-usb-preload-restoration-20260922.json`.

The next **media-only** candidate passed both host builds, but has not been
installed, activated, or booted:

```text
/nix/store/p1mr7zxizjb5wrsd54z3n2m89gzacl3c-nixos-system-baymax-recovery-archive-media-26.11.20260919.20b1ddd
```

Its overlay is `.git/agent-artifacts/baymax-services-archive-media-20260922.nix`.
It releases only `zfs-import-archive.service` and `archive.mount`, and adds a
hold on `zfs-mount.service`: 53 system holds and one user hold remain. The extra
hold prevents the parked workspace-recovery dataset from auto-mounting at its
non-legacy native mountpoint. Replica mounts and both Immich units stay masked.
The candidate suppresses both `/archive/immich` tmpfiles sources and removes
the recovery WWN read-only rule only from that uninstalled generation.

The archive-media release was followed by the approved uptime-first generation
6. That generation retains `archive-media-prewrite.service` and the archive
import guard. Keep `archive/media@immich-prewrite-20260922`, its
`baymax-immich-release-20260922` hold, and every older recovery copy.

Immich now responds on its loopback HTTP origin. This does not establish
authenticated photo access or complete backup acceptance. Retain its sealed
per-database rollback copy; never roll back the shared live PostgreSQL dataset
to undo one application migration. Native Immich 3.2.2 uses `/archive/immich`
for originals and generated files. `THUMB_LOCATION`, `ENCODED_VIDEO_LOCATION`,
`PROFILE_LOCATION`, and `BACKUP_LOCATION` are Docker Compose variables, not
native folder controls. Preserve the verified paths during recovery rather
than silently relocating data.

The approved replacement Mesh node enrolled as Baymax with virtual IPv4
`100.96.0.9`. The node ID and device-registration ID are different identifiers;
never substitute one for the other. The enrollment token was handled privately
and removed after use. Authored Nix secrets belong in the separate `nix-secrets`
repository. WARP maintains its generated registration state in
`/var/lib/cloudflare-warp`, persisted on `rpool/persist`.

The first connection attempt failed because WARP could not install nftables
`reject` rules after kernel module loading was locked. `boot.kernelModules`
now preloads `nft_reject_inet`; keep `security.lockKernelModules` enabled.
The approved generation 6 booted on 2026-09-23 with that module loaded and
`kernel.modules_disabled=1`. WARP reported `Connected` and `Network: healthy`,
and its interface held `100.96.0.9/32`. The Caddy address and readiness gate
now use that address. No gate was bypassed and no listener was widened.

The native build retained the existing kernel, initrd, signing keys, 24 system
holds, and one user hold. The new UKI passed signature verification against
the recovered db certificate; existing EFI images remained byte-identical.
The ESP backup is under
`/persist/host/recovery-warp-preload-20260923T002101Z/`. Build, installation,
and postboot receipts are retained in `.git/agent-artifacts/`.

Generation 7 uses `ClientIdentifier=mac` in both initrd and normal
`systemd-networkd`. The real boot received `192.168.4.31` in initrd at 5.54
seconds and again after unlock at 132.08 seconds. Initrd SSH listened on port
2222, then normal SSH listened on port 22. This proves one DHCP identity and one
address across the boot handoff. At that boundary, eero had not applied the old
`.24` reservation; its device view showed matching Ethernet MAC
`78:55:36:05:8d:4f` and both `.24` and `.31`. Generation 9 resolves the
deferred address issue by making `.31` permanent. Keep the eero reservation,
Baymax service address, and secondary custom DNS endpoint on `.31`.

Generation 8 fixes WARP DNS ownership without changing the router or listener
addresses. Direct DNS packets to WARP's `127.0.2.2` proxy resolved
`connectivity-check.warp-svc`, but the prior NSS order stopped at
`nss-resolve` after the physical uplink returned NXDOMAIN. Keep `dns` before
`resolve [!UNAVAIL=return]` in `system.nssDatabases.hosts`; this makes glibc
consult WARP's generated `resolv.conf` first while retaining
`systemd-resolved` as fallback. The runtime test and persistent activation both
returned the WARP internal proxy addresses, and WARP reported `Connected` and
`Network: healthy`. SSH through `100.96.0.9` also passed.

The no-reboot generation 8 activation retained the generation 7 kernel, initrd,
DHCP identity, 24 system holds, one user hold, Caddy listeners, Hister limits,
and OMP 18.2.9. The ESP backup is under
`/persist/host/recovery-warp-nss-20260923T021347Z/`. All 12 pre-existing EFI
images match that backup; six images removed by Lanzaboote were restored. The
new generation 8 boot stub passed signature verification against the recovered
db certificate, and its authenticated kernel and initrd hashes match the ESP
payloads. All eight loopback application origins responded, Cloudflare Tunnel
remained active with zero restarts, Hister remained within its recovery limits,
and all pools remained healthy. At that boundary, Caddy and the Home Managed
Network beacon could not bind the reserved LAN address because eero still leased
`.31`; this was an address-assignment issue, not a WARP failure.

Generation 9 adopts `192.168.4.31` without a reboot. Its kernel, initrd, exact
OMP 18.2.9 path, 24 system holds, user hold, archive guard, and running Immich
invocations match generation 8. Unbound, Caddy, and the managed-network beacon
are active on `.31`. After the eero restart and a DHCP renewal, Baymax retained
`.31`; the lease advertises Mini at `192.168.4.194` and Baymax at `.31`, plus
both stable ULAs, as the custom DNS servers. Both advertised IPv4 resolvers
return `.31` for all five home names over UDP and TCP. Normal client HTTPS
reached `.31`, verified every certificate, and returned the expected HTTP
responses. The eero router-local DNS proxy at `.1` is not DHCP-advertised and
continues to answer from public DNS, so it is not the custom-resolver acceptance
path. WARP, Cloudflare Tunnel, Hister, both Immich services, and all pools
remained healthy. Mini uses `.31` for the builder and host-key alias while its
managed tunnel still connects to Baymax over the stable ULA; both forwarding
directions passed.

The Atuin Gateway target migration to `100.96.0.9` has confirmed control-plane
readback. The Home LAN profile now contains exact Photos, Readeck, Budget,
Hister, and Atuin fallback entries. Each uses Baymax at `192.168.4.31`, Mini
at `192.168.4.194`, and both stable ULAs. API readback showed no application
fallbacks in the Mesh or default/away profiles. After one WARP reconnect, the
live client loaded profile `2011c12e-5fd8-4a6d-ba13-1c0fe25fa91e`, reported a
healthy network, and exposed all five records. Normal client DNS returned
`.31` for every name; HTTPS reached `.31`, verified each certificate, and
returned 200 for Photos, Budget, Hister, and Atuin and 303 for Readeck. The
default/away profile and old Mesh registration remain unchanged.

An earlier sandboxed read-only Hister audit enumerated live external IDs from
22 Bleve/Scorch indexes without decoding stored document fields or exporting
real IDs. It counted 37,429 ID entries, including 28,666 file-URL entries. Of
those, 26,692 are outside the current `/persist/save/projects-mirror` root and
still need reconciliation. These are entries across indexes, not unique
documents. No file-URL ID matched `vault/private` or a hidden path component.
This bounded result does not prove physical erasure or link provenance. No
index records were deleted. The detailed report is
`.git/agent-artifacts/hister-index-id-privacy-20260922.json`.

The user subsequently approved uptime before final reconciliation. Hister now
serves the preserved index with watched directories empty and semantic search
disabled in the staged recovery generation. Its importer remains held. The
managed service applies a 1 GiB Go memory limit, a 1536 MiB systemd high limit,
and a 2 GiB hard service limit. The postboot origin check returned HTTP 200
with zero restarts; this does not prove that bulk indexing is ready to resume.

Both Projects folders were resumed after the earlier synchronization, privacy,
and executable checks. Preserve the source ownership and permissions. Complete
the deferred index reconciliation and read-only mirror access work before
re-enabling watched-file indexing, embeddings, or the Readeck importer. Fresh
replica acceptance, pruning, and recovery-copy retirement remain separate gates.

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

Do not use the normal redeploy or automatic-upgrade commands below while any
recovery holds remain. Follow the approved staged-restoration boundary above.

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
  --target-host me@192.168.4.31 \
  --build-host me@192.168.4.31
```

After the config is pushed to `main`, Baymax can also build the reviewed GitHub
flake non-interactively through `nixos-upgrade.service`. This advances the boot
profile and reboots only inside the configured reboot window; it does not prove
the running system switched until `/run/current-system` matches the new profile.

```zsh
ssh me@192.168.4.31 '
  systemctl="$(readlink -f /run/current-system/sw/bin/systemctl)"
  sudo -n "$systemctl" start nixos-upgrade.service
'
ssh me@192.168.4.31 'systemctl status nixos-upgrade.service --no-pager -l'
ssh me@192.168.4.31 'readlink -f /nix/var/nix/profiles/system; readlink -f /run/current-system'
```

4. In Cloudflare, recreate the published application routes under `Networking -> Tunnels -> baymax-apps`.
5. Recheck the Access application scope so Readeck remains the public exception and the other app hostnames stay gated.

## Verification

Check Baymax-side service health:

```zsh
ssh me@192.168.4.31 'systemctl --failed --no-pager'
ssh me@192.168.4.31 'systemctl is-active caddy cloudflared-tunnel-baymax-apps cloudflare-warp avahi-daemon'
ssh me@192.168.4.31 'getent hosts mini-me.local'
ssh me@192.168.4.31 'systemctl is-active actual immich-server immich-machine-learning paperless-web paperless-consumer paperless-scheduler paperless-task-queue readeck miniflux ntfy-sh'
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
