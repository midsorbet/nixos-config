{
  gitCommitSigning ? {
    enable = false;
    keyPath = "~/.ssh/id_github.pub";
  },
  lib,
  pkgs,
  ...
}: let
  gitConfig = pkgs.writeText "gitconfig" ''
    ${builtins.readFile ./gitconfig}
    ${lib.optionalString gitCommitSigning.enable ''
      [user]
        signingkey = ${gitCommitSigning.keyPath}
      [gpg]
        format = ssh
      [commit]
        gpgsign = true
    ''}
  '';
in {
  wrappers.git = {
    basePackage = pkgs.git;
    env.GIT_CONFIG_GLOBAL.value = gitConfig;
  };
}
