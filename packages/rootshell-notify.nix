{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:
buildGoModule rec {
  pname = "rootshell-notify";
  version = "0.2.9";

  src = fetchFromGitHub {
    owner = "kitknox";
    repo = "rootshell";
    rev = "00904ab8fcab9329f3e7971d664e27606f827c67";
    hash = "sha256-ny+7PQGGiQxcEwDXRfiUjH4ocanW3a2wPThKwn6iL/w=";
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
