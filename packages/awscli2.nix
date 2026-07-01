{pkgs}:
pkgs.awscli2.overridePythonAttrs (old: let
  awscrt = pkgs.python3.pkgs.awscrt.overridePythonAttrs (oldAwscrt: rec {
    version = "0.32.2";
    src = oldAwscrt.src.override {
      inherit version;
      hash = "sha256-pPSIBeimYjeSPwO3tpLSE5lM/0LR/wgSXR1gx0/K+HI=";
    };
  });
in rec {
  version = "2.35.14";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-IBBd4NnbdLs0F094QA1bE7O8Oux93lAdmGduePEpb/8=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
