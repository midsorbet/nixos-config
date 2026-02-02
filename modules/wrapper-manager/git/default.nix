{pkgs, ...}: let
  localSecrets = import ../../../secrets.local.nix;
  baseConfig = builtins.readFile ./gitconfig;
  gitConfig = pkgs.writeText "gitconfig" ''
    ${baseConfig}
    [user]
      name = ${localSecrets.name}
      email = ${localSecrets.email}
  '';
in {
  wrappers.git = {
    basePackage = pkgs.git;
    env.GIT_CONFIG_GLOBAL.value = gitConfig;
  };
}
