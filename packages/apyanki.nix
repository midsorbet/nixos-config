{
  callPackage,
  fetchFromGitHub,
  inputs,
  lib,
  python314,
}: let
  version = "0.21.0";
  src = fetchFromGitHub {
    owner = "lervag";
    repo = "apy";
    tag = "v${version}";
    hash = "sha256-LqMXy0d3UUgkI7vriQaNK04NE9YKWZlJK717BKbAvxM=";
  };

  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = src;
  };

  pyprojectOverlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  pythonSet =
    (callPackage inputs.pyproject-nix.build.packages {
      python = python314;
    })
    .overrideScope
    (lib.composeManyExtensions [
      inputs.pyproject-build-systems.overlays.wheel
      pyprojectOverlay
    ]);
in
  pythonSet.mkVirtualEnv "apyanki-${version}" workspace.deps.default
