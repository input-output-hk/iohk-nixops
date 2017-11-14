{ IOHKaccessKeyId, ... }:

with (import ./../lib.nix);
let region = "eu-central-1";
    accessKeyId = IOHKaccessKeyId;
in {
  network.description = "IOHK infrastructure production";

  hydra = { config, pkgs, resources, ... }: {

    imports = [
      ./../modules/papertrail.nix
      ./../modules/datadog.nix
    ];

    services.dd-agent.tags = ["env:production" "depl:${config.deployment.name}"];

    deployment.ec2.elasticIPv4 = resources.elasticIPs.hydra-ip;

    deployment.route53.accessKeyId = config.deployment.ec2.accessKeyId;
    deployment.route53.hostName = "hydra.aws.iohkdev.io";
  };

  cardano-deployer = { config, pkgs, resources, ... }: {
    imports = [
      ./../modules/datadog.nix
      ./../modules/papertrail.nix
    ];

    services.dd-agent.tags = ["env:production" "depl:${config.deployment.name}"];

    deployment.keys.tarsnap = {
      keyFile = ./../static/tarsnap-cardano-deployer.secret;
      destDir = "/var/lib/keys";
    };

    deployment.ec2.elasticIPv4 = resources.elasticIPs.cardanod-ip;
  };

  kite = { config, pkgs, resources, ... }: {

    imports = [
      ./../modules/papertrail.nix
      ./../modules/datadog.nix
    ];

    services.dd-agent.tags = ["env:production" "depl:${config.deployment.name}"];

    deployment.ec2.elasticIPv4 = resources.elasticIPs.kite-ip;

    deployment.route53.accessKeyId = config.deployment.ec2.accessKeyId;
    deployment.route53.hostName = "kite.aws.iohkdev.io";
  };

  resources = {
    datadogMonitors = (with (import ./../modules/datadog-monitors.nix); {
      disk = mkMonitor disk_monitor;
      ntp = mkMonitor ntp_monitor;
    });
    elasticIPs = {
      kite-ip     = { inherit region accessKeyId; };
      hydra-ip    = { inherit region accessKeyId; };
      cardanod-ip = { inherit region accessKeyId; };
    };
  };
}
