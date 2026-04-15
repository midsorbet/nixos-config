{secrets, ...}: {
  age.identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];

  age.secrets = {
    edge-pass.file = "${secrets}/edge-pass.age";
  };
}
