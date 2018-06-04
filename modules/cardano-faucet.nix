with (import ./../lib.nix);

globals: params:
{ pkgs, config, resources, options, ...}:

let
  iohkpkgs = import ../. {};
  faucet-drv = iohkpkgs.cardano-sl-faucet;
  cfg = config.services.faucet;
  tlsPath = fileName: "${cfg.home}/wallet/tls/${fileName}";
  walletPort = cfg.wallet-port;
  ekgPort = 8001;
  loggingCfg = pkgs.writeText "logging.cfg"
    ''
    termSeveritiesErr: All
    loggerTree:
      severity: Info+   # severities for «root» logger
      withdraw:          # logger for the withdraw action
        severity: Debug+   # severities withdraw logger
    '';
  cfgFile = pkgs.writeText "config.json" (builtins.toJSON cfg.faucet-config);
  # walletCfg cribbed from cardano-benchmark
  walletCfg = {
    walletListen = "127.0.0.1:${toString walletPort}";
    ekgListen = "127.0.0.1:${toString ekgPort}";
    # TODO: how do environment and confKey interact?
    # from connect-to-cluster it looks like setting environment to override
    # means that you need to specify relays?
    # environment = cfg.environment;
    # confKey = "bench";
    stateDir = "${cfg.home}/wallet";
    # TODO: Is this needed?
    # extraParams = "--system-start ${toString cfg.systemStart}";
  };
in
{
    imports = [
      ./common.nix
      ./amazon-base.nix
      ./network-wide.nix
      ./datadog.nix
    ];

  options.services.faucet = with types; {
    enable = mkOption { type = bool; default = true; };
    home = mkOption { type = string; default = "/var/lib/faucet"; };
    # TODO: Do we need this?
    environment = mkOption { type = string; default = "demo"; };

    faucet-config = mkOption {
      description = "Configuration for the faucet";
      type = submodule {
        options = {
          wallet-host = mkOption { type = str; default = "127.0.0.1"; };
          wallet-port = mkOption { type = int; default = 8090; };
          payment-amount = mkOption { type = int; default = 1000; };
          payment-variation = mkOption { type = int; default = 500; };
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
          logging-config = mkOption { type = path; default = loggingCfg; };
          public-certificate = mkOption { type = path; default = tlsPath "server.cert"; };
          private-key = mkOption { type = path; default = tlsPath "server.key"; };

        };
      };
    };
  };

  config = {

    global.dnsHostname = "faucet";

    users = {
      users.faucet = {
        group = "faucet";
        createHome = true;
        home = cfg.home;
        extraGroups = [ "keys" ];
      };
      groups.faucet = {};
    };

    # Not sure if I need to start this myself or not?
    services.statsd = {
      enable = true;
      backends = ["graphite"];
      graphiteHost = "127.0.0.1";
      graphitePort = 2003;
    };

    systemd.services = {
      wallet = mkIf cfg.enable {
        description = "Cardano faucet wallet";
        after         = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "faucet";
          Group = "faucet";
          ExecStart = iohkpkgs.connectScripts.stagingWallet.override params;
        };
      };
      faucet = mkIf cfg.enable {
        description = "Cardano faucet";
        after         = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        requires = [ "wallet.service"];
        serviceConfig = {
          User = "faucet";
          Group = "faucet";
        };
        script = ''
        ${faucet-drv}/bin/faucet --config ${cfgFile} +RTS -T
        '';
      };
    };


    networking.firewall.allowedTCPPorts = mkIf  cfg.enable [
      # TODO: Do I need to open ports to stuff that's only running on localhost?
      cfg.faucet-config.port ekgPort walletPort
    ];

  };
}
