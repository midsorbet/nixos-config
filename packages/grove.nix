{
  buildGoModule,
  fetchFromGitHub,
  git,
  lib,
  makeWrapper,
}:
buildGoModule rec {
  pname = "grove";
  version = "1.1.18";

  src = fetchFromGitHub {
    owner = "nicksenap";
    repo = "grove";
    tag = "v${version}";
    hash = "sha256-1ovtWgDimcJjTVbaAvNo4uIy6aqZPepsi6U2ITgTaPc=";
  };

  vendorHash = "sha256-34i8R0orxZ5G0g/j9jOZtjV00F/vS7fB+j/MQ+CEOVo=";

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
