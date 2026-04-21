{pkgs, ...}: let
  gitConfig = pkgs.writeText "gitconfig" (builtins.readFile ./gitconfig);
in {
  wrappers.git = {
    basePackage = pkgs.gitFull;
    env.GIT_CONFIG_GLOBAL.value = gitConfig;
  };
}
