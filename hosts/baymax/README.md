# Baymax

## Live ISO

Append this to the kernel command line in the boot menu to avoid issues with the Seagate External HDD:

```text
usb-storage.quirks=0bc2:2344:u,125f:a36a:u
```

- Highlight the ISO boot entry and press `e`.
- Append the quirk string to the Linux kernel command line.
- Boot with `Ctrl+x`

## Remote Unlock Setup

One-time setup:

```bash
sudo install -d -m 700 /persist/secrets/initrd
sudo ssh-keygen -t ed25519 -N "" -f /persist/secrets/initrd/ssh_host_ed25519_key
sudo chmod 600 /persist/secrets/initrd/ssh_host_ed25519_key
sudo chmod 644 /persist/secrets/initrd/ssh_host_ed25519_key.pub
```

- Do not reuse other keys for initrd unlock
