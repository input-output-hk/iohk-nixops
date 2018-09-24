{ config, pkgs, lib, ... }:

with lib;

let cfg = config.services.github-webhook-util;
    iohkPkgs = import ../. {};

in {
  options.services.github-webhook-util = {
    enable = mkEnableOption "enable github webhook util";
    domain = mkOption {
      description = "Domain to host under";
      type = types.str;
    };
    secrets = mkOption {
      description = "Environment variable secrets";
      type = types.path;
    };
  };
  config = mkIf cfg.enable {
    services.influxdb.enable = true;
    services.nginx.virtualHosts."${cfg.domain}" = {
      locations."/github-webhooks" = {
        proxyPass = "http://127.0.0.1:8082";
      };
    };
    systemd.services."github-webhook-util" = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${iohkPkgs.github-webhook-util}/bin/github-webhook-util";
        EnvironmentFile = cfg.secrets;
      };
    };
  };
}
