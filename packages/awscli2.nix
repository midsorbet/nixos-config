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
  version = "2.36.7";
  src = pkgs.fetchFromGitHub {
    owner = "aws";
    repo = "aws-cli";
    tag = version;
    hash = "sha256-GtAuGqgOmB2UT/R5qF6EZt2MsUdViJ/Wvka0Ltz1J8I=";
  };

  dependencies = [awscrt] ++ pkgs.lib.tail old.dependencies;
})
