{pkgs}:
pkgs.awscli2.overridePythonAttrs (old: let
  awscrt = pkgs.python3.pkgs.awscrt.overridePythonAttrs (oldAwscrt: rec {
    version = "0.35.0";
    src = oldAwscrt.src.override {
      inherit version;
      hash = "sha256-dhrg3aF/2d+v9Luyo3bijkTf133GQQt7xAgpeh/VYA4=";
    };
  });
in rec {
  version = "2.35.15";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-uQEf1X5FW3mjFPKI5aEqlqcIh8N/PIiH7KIUVOvqxzQ=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
