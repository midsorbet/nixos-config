{pkgs}:
(pkgs.awscli2.override {python3 = pkgs.python313;}).overridePythonAttrs (old: let
  awscrt = pkgs.python313Packages.awscrt.overridePythonAttrs (oldAwscrt: rec {
    version = "0.36.0";
    src = oldAwscrt.src.override {
      inherit version;
      hash = "sha256-rSGYRh87KihR83iR113LkXO/4kdNhVCtYmC/mXC0Bko=";
    };
  });
in rec {
  version = "2.36.6";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-SQWjz0tak41epSJxJLjIHlM3X1IVC88PQdMkTDwcCFE=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
