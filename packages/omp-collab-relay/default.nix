{pkgs}: let
  relay = pkgs.writeShellApplication {
    name = "omp-collab-relay";
    runtimeInputs = [pkgs.bun];
    text = ''
      exec bun run ${./relay.ts} "$@"
    '';
    meta = {
      description = "Hardened loopback WebSocket relay for OMP collab sessions";
      mainProgram = "omp-collab-relay";
    };
  };

  tunnel = pkgs.writeShellApplication {
    name = "omp-collab-tunnel";
    runtimeInputs = [
      relay
      pkgs.cloudflared
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = builtins.readFile ./tunnel.sh;
    meta = {
      description = "On-demand OMP collab relay behind a temporary Cloudflare Quick Tunnel";
      mainProgram = "omp-collab-tunnel";
    };
  };
in {
  omp-collab-relay = relay;
  omp-collab-tunnel = tunnel;
}
