{ ... }:

with (import ../lib.nix);
let
  mkHydra = hostname: { config, pkgs, resources, ... }: { };
  mkUplink = mkMkUplink {
    central = "192.168.20.1";
    subnet = "192.168.20";
    # TODO, `monitoring-ip` will be wrong if monitoring isnt using an elastic ip by that name
    endpoint = "monitoring-ip:51820";
  };
in {
  network.description = "IOHK infrastructure production";

  defaults = {
    _file = ./infrastructure-env-production.nix;
    # TODO imports = [ ../modules/network-wide.nix ];

    services.monitoring-exporters = {
      papertrail.enable = true;
    };
  };

  hydra        = mkHydra "hydra";
  mantis-hydra = mkHydra "mantis-hydra";

  cardano-deployer = { config, pkgs, resources, ... }: {
    imports = [
      ../modules/deployer.nix
    ];

    deployment.keys.tarsnap = {
      keyFile = ../static/tarsnap-cardano-deployer.secret;
      destDir = "/var/lib/keys";
    };

    users = {
      users.live-production = {
        description     = "cardano live-production";
        group           = "live-production";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devOpsKeys;
      };
      groups.live-production = {};
      users.staging = {
        description     = "cardano staging";
        group           = "staging";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devKeys;
      };
      groups.staging = {};
    };

    services.tarsnap = {
      enable = true;
      keyfile = "/var/lib/keys/tarsnap";
      archives.cardano-deployer = {
        directories = [
          "/home/live-production/.aws"
          "/home/live-production/.nixops"
          "/etc/"
        ];
      };
    };

  };

  bors-ng = { config, pkgs, resources, ... }: let
    hostName = "bors-ng.aws.iohkdev.io";
    keysDir = "/var/lib/keys";
  in {

    services.bors-ng = {
      publicHost = hostName;
      secretKeyBaseFile = "${keysDir}/bors-ng-secret-key-base";
      github = {
        clientID = "Iv1.17382ed95b58d1a8";
        clientSecretFile = "${keysDir}/bors-ng-github-client-secret";
        integrationID = 17473;
        integrationPEMFile = "${keysDir}/bors-ng-github-integration.pem";
        webhookSecretFile = "${keysDir}/bors-ng-github-webhook-secret";
      };
    };
    systemd.services.bors-ng.after = [ "keys.target" ];
    systemd.services.bors-ng.requires = [ "keys.target" ];
    users.users.bors-ng.extraGroups = [ "keys" ];

    deployment.keys.bors-ng-secret-key-base = {
      keyFile = ../static/bors-ng-secret-key-base;
      destDir = "/var/lib/keys";
      user = "bors-ng";
    };
    deployment.keys.bors-ng-github-client-secret = {
      keyFile = ../static/bors-ng-github-client-secret;
      destDir = "/var/lib/keys";
      user = "bors-ng";
    };
    deployment.keys."bors-ng-github-integration.pem" = {
      keyFile = ../static/bors-ng-github-integration.pem;
      destDir = "/var/lib/keys";
      user = "bors-ng";
    };
    deployment.keys.bors-ng-github-webhook-secret = {
      keyFile = ../static/bors-ng-github-webhook-secret;
      destDir = "/var/lib/keys";
      user = "bors-ng";
    };
  };
  log-classifier = { config, pkgs, resources, ... }: let
    hostName = "log-classifier.aws.iohkdev.io";
    keysDir = "/var/lib/keys";
  in {
    imports = [
      ../modules/log-classifier.nix
      ../modules/common.nix
    ];

    services.log-classifier.domain = "log-classifier.aws.iohkdev.io";
  };

  monitoring = { lib, config, pkgs, resources, ... }: {
    imports = [
      ../modules/monitoring-services.nix
      ../modules/exchange-monitor.nix
    ];

    deployment.keys."monitoring.wgprivate" = {
      destDir = "/etc/wireguard";
      keyFile = ../static/monitoring.wgprivate;
    };
    networking.wireguard.interfaces.wg0 = {
      peers = let
        genPeer = n: path: {
          allowedIPs = [ "192.168.20.${toString n}/32" ];
          publicKey = lib.strings.removeSuffix "\n" (builtins.readFile path);
        };
      in [
        # main hydra build-slaves
        (genPeer 11 ../static/builder-packet-c1-small-x86.wgpublic)
        (genPeer 12 ../static/builder-packet-c1-small-x86-2.wgpublic)
        (genPeer 13 ../static/builder-packet-c1-small-x86-3.wgpublic)
        (genPeer 14 ../static/builder-packet-c1-small-x86-4.wgpublic)
        (genPeer 15 ../static/builder-packet-c1-small-x86-5.wgpublic)
        # buildkite agents
        (genPeer 31 ../static/buildkite-packet-1.wgpublic)
        (genPeer 32 ../static/buildkite-packet-2.wgpublic)
        (genPeer 33 ../static/buildkite-packet-3.wgpublic)
        # mantis hydra build-slaves
        (genPeer 51 ../static/mantis-slave-packet-1.wgpublic)
        (genPeer 52 ../static/mantis-slave-packet-2.wgpublic)
      ];
    };

    services = {
      exchange-monitor.enable = true;
      monitoring-services = {
        enable = true;
        enableWireguard = true;
        # NOTE: The Grafana user and password settings only take effect on the initial deployment.
        grafanaCreds = makeCreds "grafana" { user = "changeme"; password = "changeme"; };
        graylogCreds = makeCreds "graylog" { user = "changeme"; password = "changeme"; };
        grafanaAutoLogin = true;
        applicationRules = [
          {
            alert = "exchange-down-binance";
            expr = "binance_withdraws == 0 or binance_deposits == 0";
            for = "10m";
            labels.severity = "exchange-down";
            annotations = {
              description = "{{$labels.alias}} withdraws/deposits down for >=10mins";
            };
          }
          {
            alert = "exchange-down-bittrex";
            expr = "bittrex_active == 0";
            for = "10m";
            labels.severity = "exchange-down";
            annotations = {
              description = "{{$labels.alias}} withdraws/deposits down for >=10mins";
            };
          }
          {
            alert = "exchange-down-bitthumb";
            expr = "bithumb_active == 0";
            for = "10m";
            labels.severity = "exchange-down";
            annotations = {
              description = "{{$labels.alias}} withdraws/deposits down for >=10mins";
            };
          }
          {
            alert = "exchange-down-hitbtc";
            expr = "bithumb_active == 0";
            for = "10m";
            labels.severity = "exchange-down";
            annotations = {
              description = "{{$labels.alias}} withdraws/deposits down for >=10mins";
            };
          }         
        ];
        alertmanager = {
          extraRoutes = [
            {
              match.severity = "exchange-down";
              receiver = "exchange-down";
            }
          ];
          extraReceivers = [
            {
              name = "exchange-down";
              pagerduty_configs = [
                {
                  service_key = if (builtins.pathExists ../static/pager-duty.nix)
                    then ((import ../static/pager-duty.nix).exchangeKey)
                    else { exchangeKey = null; };
                }
              ];
            }
          ];
        };
      };
    };
  };

  builder-packet-c1-small-x86 = mkUplink 11 ../static/builder-packet-c1-small-x86.wgprivate;
  builder-packet-c1-small-x86-2 = mkUplink 12 ../static/builder-packet-c1-small-x86-2.wgprivate;
  builder-packet-c1-small-x86-3 = mkUplink 13 ../static/builder-packet-c1-small-x86-3.wgprivate;
  builder-packet-c1-small-x86-4 = mkUplink 14 ../static/builder-packet-c1-small-x86-4.wgprivate;
  builder-packet-c1-small-x86-5 = mkUplink 15 ../static/builder-packet-c1-small-x86-5.wgprivate;

  buildkite-packet-1 = mkUplink 31 ../static/buildkite-packet-1.wgprivate;
  buildkite-packet-2 = mkUplink 32 ../static/buildkite-packet-2.wgprivate;
  buildkite-packet-3 = mkUplink 33 ../static/buildkite-packet-3.wgprivate;

  mantis-slave-packet-1 = mkUplink 51 ../static/mantis-slave-packet-1.wgprivate;
  mantis-slave-packet-2 = mkUplink 52 ../static/mantis-slave-packet-2.wgprivate;
}
