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
  version = "2.34.43";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-XtHmraDRjzHHoKLHFCTb/Ut3gAzJu+jhiyFK+rcZrss=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
