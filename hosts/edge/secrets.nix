{secrets, ...}: {
  age.identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];

  age.secrets = {
    edge-tailscale-key.file = "${secrets}/edge-tailscale-key.age";
    edge-pass.file = "${secrets}/edge-pass.age";
  };
}
