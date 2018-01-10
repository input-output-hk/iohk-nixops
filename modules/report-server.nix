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
        default = (import ./../default.nix {}).cardano-report-server-static;
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

    networking.firewall.allowedTCPPorts = [
      cfg.port
    ];

    users = {
      users.report-server = {
        group = "report-server";
        home = config.services.report-server.logsdir;
        createHome = true;
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
        ExecStart = ''
          ${cfg.executable}/bin/cardano-report-server -p ${toString cfg.port} --logsdir ${cfg.logsdir}
        '';
      };
    };
  };
}
