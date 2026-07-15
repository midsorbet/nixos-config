{pkgs}:
(pkgs.awscli2.override {python3 = pkgs.python313;}).overridePythonAttrs (old: let
  awscrt = pkgs.python313Packages.awscrt.overridePythonAttrs (oldAwscrt: rec {
    version = "0.35.0";
    src = oldAwscrt.src.override {
      inherit version;
      hash = "sha256-dhrg3aF/2d+v9Luyo3bijkTf133GQQt7xAgpeh/VYA4=";
    };
  });
in rec {
  version = "2.35.23";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-D9sAZ2RaRvDTtwMFt9AWhimSx8NzKjjJkApx9a7m8a4=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
