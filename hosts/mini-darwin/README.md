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
