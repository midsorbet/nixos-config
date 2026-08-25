{secrets, ...}: let
  user = "me";
in {
  age.identityPaths = [
    "/persist/host/secrets/initrd/ssh_host_ed25519_key"
    "/persist/host/secrets/ssh/ssh_host_ed25519_key"
  ];

  age.secrets."github-ssh-key" = {
    symlink = false;
    path = "/home/${user}/.ssh/id_github";
    file = "${secrets}/github-ssh-key.age";
    mode = "600";
    owner = "${user}";
    group = "wheel";
  };

  age.secrets."readeck-env".file = "${secrets}/readeck.age";
  age.secrets."miniflux-admin".file = "${secrets}/miniflux.age";
  age.secrets."paperless".file = "${secrets}/paperless.age";
  age.secrets."ntfy-auth".file = "${secrets}/ntfy-auth.age";
  age.secrets."ntfy-publisher-token".file = "${secrets}/ntfy-publisher-token.age";
  age.secrets."hetzner-borg-key".file = "${secrets}/hetzner-borg-key.age";
  age.secrets."hetzner-borg-pass".file = "${secrets}/hetzner-borg-pass.age";
  age.secrets."baymax-borg-pass".file = "${secrets}/baymax-borg-pass.age";
  age.secrets."hetzner-borg-hosts".file = "${secrets}/hetzner-borg-hosts.age";
  age.secrets."baymax-tunnel".file = "${secrets}/baymax-tunnel.age";
  age.secrets."cloudflare-acme-dns-token".file = "${secrets}/cloudflare-acme-dns-token.age";
  age.secrets."home-managed-network-key" = {
    file = "${secrets}/home-managed-network-key.age";
    mode = "400";
    owner = "caddy";
    group = "caddy";
  };
}
