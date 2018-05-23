with (import ./../lib.nix);

{ config, pkgs, lib, ... }:

let
  cardanoPackages = import ./../default.nix {};
  faucet-drv = cardanoPackages.cardano-sl-faucet;
  cfg = config.services.cardano-faucet;
  cfgFile = builtins.toFile "config.json" (builtins.toJSON cfg.faucet-config);
in
{
  options.services.cardano-faucet = with types; {
    enable = mkOption { type = bool; default = true; };
    faucet-config = mkOption {
      description = "Configuration for the faucet";
      type = submodule {
        options = {
          wallet-host = mkOption { type = str; default = "127.0.0.1"; };
          wallet-port = mkOption { type = int; default = 8090; };
          port = mkOption {
            type = int;
            default = 8081 ;
            description = "Port to serve the faucet on";
          };
          statsd = mkOption {
            description = "Statsd settings";
            type = submodule {
              options = {
                host = mkOption { type = str; default = "127.0.0.1"; };
                port = mkOption { type = int; default = 8125; };
                flush-interval = mkOption { type = int; default = 1000; };
              };
            };
            default = {
              host = "127.0.0.1";
              port = 8125;
              flush-interval = 1000;
            };
          };
          source-wallet-config = mkOption { type = path; };
          logging-config = mkOption { type = path; };
          public-certificate = mkOption { type = path; };
          private-key = mkOption { type = path; };

        };
      };
    };
  };

  config = {
    systemd.services.cardano-faucet = mkIf cfg.enable {
      description = "Cardano faucet";
      after         = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "cardano-faucet";
        Group = "cardano-faucet";
      };
      script = ''
      ${faucet-drv}/bin/faucet --config ${cfgFile} +RTS -T
      '';
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.enable [
      cfg.faucet-config.port
    ];

    # TODO: Should this move to a separate implementation module
    # (i.e. where the faucet is enabled in nixops?)
    services.cardano-faucet.faucet-config = {
      source-wallet-config = builtins.toString ../../cardano-sl/faucet/wallet-source.json;
      logging-config = builtins.toString ../../cardano-sl/faucet/logging.cfg;
      public-certificate = builtins.toString ../../cardano-sl/faucet/tls/ca.crt;
      private-key = builtins.toString ../../cardano-sl/faucet/tls/server.key;
    };
  };
}
