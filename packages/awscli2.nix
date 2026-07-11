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
  version = "2.35.21";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-HRyRO8UIfCSqkQdd5uQszgB4nwq90NkASz8DywVtF3A=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
