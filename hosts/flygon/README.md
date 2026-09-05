# Flygon Recovery Safety

Flygon is a Framework Laptop 13 managed by `hosts/flygon/default.nix`. Preserve
these boundaries for future disk, boot, and data-recovery work.

## Disk and boot changes

- Re-identify the target NVMe by stable device path, model, serial, and size
  before any destructive operation. Never rely on `/dev/nvme0n1` alone.
- Keep LUKS creation passphrases only in installer tmpfs and remove the file
  before reboot. The installed system uses an interactive boot unlock.
- Before a GPT edit, capture the table and verify partition type GUIDs, unique
  GUIDs, starts, ends, sizes, attributes, and names against the intended layout.
  Verify the LUKS header, filesystem bounds, and `sgdisk --verify`. Do not reboot
  after a GPT edit unless this same gate passes.

## Restore boundaries

- Extract a root archive into a staging directory, never over the fresh root.
- Restore ordinary user data first. Inspect ownership and permissions before
  restoring SSH keys or individual application profiles. Do not copy the old
  home wholesale over Hjem- or Nix-managed state.
- Use staged `/etc`, `/root`, and `/var/lib` only for deliberate per-service
  recovery. Do not restore historical Docker state or an old EFI tree.
- Keep archives, hashes, manifests, and inventories until the full physical
  acceptance checklist is complete and the rollback window is explicitly closed.
