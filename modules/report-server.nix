with (import ./../lib.nix);

params:
{ pkgs, config, resources, options, ...}:

let
  cfg = config.services.report-server;
in {
  imports = [
    ./common.nix
    ./amazon-base.nix
    ./network-wide.nix
  ];

  options = {
    services.report-server = {
      logsdir = mkOption {
        type = types.path;
        default = "/var/lib/report-server";
      };
      port = mkOption {
        type = types.int;
        default = 8080;
      };
      executable = mkOption {
        type = types.package;
        default = (import ../default.nix {}).cardano-report-server-static;
      };
      zendesk = {
        email = mkOption {
          type = types.str;
          default = "";
          example = "agent@email.com";
          description = ''
            The e-mail associated with the Zendesk account.
          '';
        };
        tokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/keys/zendesk-token";
          description = ''
            An access token for Zendesk.
          '';
        };
        accountName = mkOption {
          type = types.str;
          default = "";
          example = "iohk";
          description = ''
            Zendesk account name. This is the first part of NAME.zendesk.com.
          '';
        };
        sendLogs = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Send logs from custom reports to Zendesk.
          '';
        };
      };
    };
  };

  config = {

    # TODO: remove
    global = {
      organisation             = params.org;
      dnsHostname              = mkForce "report-server";
    };

    deployment.ec2.region         = mkForce params.region;
    deployment.ec2.accessKeyId    = params.accessKeyId;
    deployment.ec2.keyPair        = resources.ec2KeyPairs.${params.keyPairName};
    deployment.ec2.securityGroups =
      let sgNames = [ "allow-to-report-server-${config.deployment.ec2.region}" ];
      in map (resolveSGName resources)
         (if config.global.omitDetailedSecurityGroups
          then [ "allow-all-${params.region}-${params.org}" ]
          else sgNames);

    deployment.ec2.ebsInitialRootDiskSize = 200;

    deployment.keys.zendesk-token = {
      keyFile = ./. + "/../static/zendesk-token.secret";
      user = "report-server";
      destDir = "/var/lib/keys";
    };

    networking.firewall.allowedTCPPorts = [
      cfg.port
    ];

    users = {
      users.report-server = {
        group = "report-server";
        home = config.services.report-server.logsdir;
        createHome = true;
        extraGroups = [ "keys" ];
      };
      groups.report-server = {};
    };

    systemd.services.report-server = {
      description   = "Cardano report server";
      after         = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = cfg.logsdir;
      serviceConfig = {
        User = "report-server";
        Group = "report-server";
      };
      script = let
        zdEmail     = if cfg.zendesk.email != ""       then "--zd-email \"${cfg.zendesk.email}\"" else "";
        zdAccount   = if cfg.zendesk.accountName != "" then "--zd-account \"${cfg.zendesk.accountName}\"" else "";
        zdSendLogs  = if cfg.zendesk.sendLogs          then "--zd-send-logs" else "";
        zdTokenPath = if cfg.zendesk.tokenFile != null && cfg.zendesk.tokenFile != ""
                                                       then "--zd-token-path ${cfg.zendesk.tokenFile}" else "";
      in ''
        exec ${cfg.executable}/bin/cardano-report-server \
            -p ${toString cfg.port} \
            ${zdEmail} ${zdAccount} ${zdSendLogs} ${zdTokenPath} \
            --logsdir ${cfg.logsdir}
      '';
    };
    systemd.services.zendeskTicketTest = let  # DEVOPS-977
      payload = pkgs.writeText "payload.txt" (builtins.toJSON {
        application = "cardano-node";
        version = "0.0.1";
        build = "1";
        os = "Linux 4.9.2 NixOS";
        logs = [ "" ];
        date = "2018-05-03T00:00:00";
        magic = 2000000000;
        type = {
          type = "customreport";
          email = "iohk.zendesk.test@gmail.com";
          subject = "Mainnet Cardano Reporting Server Diagnostic Test";
          problem = "Right is right even if no-one is doing it; wrong is wrong even if everyone is doing it.";
        };
      });
    in {
      startAt = [ "hourly" ];
      path = with pkgs; [ curl jq ];
      script = ''
        fail() {
          echo FAILURE sending dummy report to report server
        }
        curl -v -F payload="<${payload}" http://${config.deployment.route53.hostName}:8080/report > /tmp/last-test-reply.json || fail
        jq . < /tmp/last-test-reply.json
      '';
    };

    # TODO, merge with the monitor in modules/cardano.nix
    services.dd-agent.processConfig = ''
    init_config:

    instances:
    - name:            cardano-report-server
      search_string: ['cardano-report-server']
      exact_match: True
      thresholds:
        critical: [1, 1]
    '';

    assertions = [
      { assertion =
          (cfg.zendesk.email != "" && cfg.zendesk.tokenFile != null && cfg.zendesk.accountName != "") ||
          (cfg.zendesk.email == "" && cfg.zendesk.tokenFile == null && cfg.zendesk.accountName == "");
        message = ''
          Either all or none of `services.report-server.zendesk.email',
          `services.report-server.zendesk.tokenFile',
          `services.report-server.zendesk.accountName' must be defined.
        '';
      }
    ];
  };
}
