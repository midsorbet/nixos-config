{
  buildGoModule,
  fetchFromGitHub,
  git,
  lib,
  makeWrapper,
}:
buildGoModule rec {
  pname = "grove";
  version = "1.1.15";

  src = fetchFromGitHub {
    owner = "nicksenap";
    repo = "grove";
    tag = "v${version}";
    hash = "sha256-ysAHjMn3Iiydvr9Z1yaXzPPh7vChJHPM+5HfA/rdGAM=";
  };

  vendorHash = "sha256-RJWUJP3/7sKNdDHmf1+S610tt4b+cisV/U9DGah91cA=";

  subPackages = ["cmd/gw"];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/nicksenap/grove/cmd.Version=${version}"
  ];

  nativeBuildInputs = [makeWrapper];

  postInstall = ''
    wrapProgram $out/bin/gw --prefix PATH : ${lib.makeBinPath [git]}
  '';

  meta = {
    description = "Git worktree workspace orchestrator";
    homepage = "https://github.com/nicksenap/grove";
    license = lib.licenses.mit;
    mainProgram = "gw";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
