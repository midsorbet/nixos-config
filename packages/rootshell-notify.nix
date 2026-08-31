{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:
buildGoModule rec {
  pname = "rootshell-notify";
  version = "0.2.8";

  src = fetchFromGitHub {
    owner = "kitknox";
    repo = "rootshell";
    rev = "61f36e50e050bf0f36c1c95c10de436f8353c236";
    hash = "sha256-SwlRDQ4QVhJ1zAOPChoUvGfoNX8QntFZuUp+7QjeQG8=";
  };

  modRoot = "push";
  vendorHash = null;
  subPackages = ["cmd/rootshell-notify"];

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  meta = {
    description = "Encrypted push notification client for rootshell";
    homepage = "https://www.rootshell.com/";
    license = lib.licenses.mit;
    maintainers = [];
    mainProgram = "rootshell-notify";
  };
}
