{ pkgs, lib, config, ... }:

let
  cfg = config.services.jormungandr-monitor;

  monitorAddresses = let
    inherit (lib) elemAt filter readFile fromJSON;
    genesis = fromJSON (readFile ./genesis.yaml);
    initial = map (i: if i ? fund then i.fund else null) genesis.initial;
    withFunds = filter (f: f != null) initial;
    in map (f: f.address) (lib.flatten withFunds);

in {
  options = {
    services.jormungandr-monitor = {
      enable = lib.mkEnableOption "jormungandr monitor";
    };
  };
  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ 8000 ];
    users.users.jormungandr-monitor = {
      home = "/var/empty";
      isSystemUser = true;
    };
    systemd.services.jormungandr-monitor = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        exec ${pkgs.callPackage ./jormungandr-monitor {}}
      '';

      environment.MONITOR_ADDRESSES = lib.concatStringsSep " " monitorAddresses;
      environment.JORMUNGANDR_API = "http://${config.networking.privateIPv4}:3001/api";

      serviceConfig = {
        User = "jormungandr-monitor";
        Restart = "always";
        RestartSec = "15s";
      };
    };
  };
}
