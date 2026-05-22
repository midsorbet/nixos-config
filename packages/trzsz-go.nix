{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:
buildGoModule rec {
  pname = "trzsz-go";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "trzsz";
    repo = "trzsz-go";
    tag = "v${version}";
    hash = "sha256-CokZAXT61UKSsKnzE5mPMdAZecGX/8mgDkG4yDSat5M=";
  };

  vendorHash = "sha256-eqQ5PpHNLp2QebC6fZcVYT9hHAeXfM6GLiji4WzGSRQ=";

  subPackages = [
    "cmd/trz"
    "cmd/trzsz"
    "cmd/tsz"
  ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "trzsz file transfer tools compatible with tmux";
    homepage = "https://trzsz.github.io/go";
    license = lib.licenses.mit;
    maintainers = [];
    mainProgram = "trzsz";
  };
}
