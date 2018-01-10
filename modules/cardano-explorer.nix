with (import ./../lib.nix);

globals: params:
{ config, pkgs, lib, ... }:

let
  explorer-drv = (import ./../default.nix {}).cardano-sl-explorer-static;
in
{
  global.dnsHostname   = mkForce   "cardano-explorer";

  services.cardano-node.executable = "${explorer-drv}/bin/cardano-explorer";

  networking.firewall.allowedTCPPorts = [
    80 # nginx
  ];

  services.nginx = {
    enable = true;
    virtualHosts =
     let vhostDomainName = if config.global.dnsDomainname != null
                           then config.global.dnsDomainname else "iohkdev.io";
     in {
      "cardano-explorer.${vhostDomainName}" = {
        # TLS provided by cloudfront
        locations = {
          "/" = {
            # TODO: one day we'll build purescript with Nix!
            # but today, this is built by ./scripts/generate-explorer-frontend.sh
            root = ./../cardano-sl/explorer/frontend/dist;
            # Serve static files or fallback to browser history api
            tryFiles = "$uri /index.html";
          };
          "/api/".proxyPass = "http://127.0.0.1:8100";
          "/socket.io/".proxyPass = "http://127.0.0.1:8110";
        };
        # Otherwise nginx serves files with timestamps unixtime+1 from /nix/store
        extraConfig = ''
          if_modified_since off;
          add_header Last-Modified "";
          etag off;
        '';
      };
    };
    eventsConfig = ''
      worker_connections 1024;
    '';
    appendConfig = ''
      worker_processes 4;
      worker_rlimit_nofile 2048;
    '';
  };
}
