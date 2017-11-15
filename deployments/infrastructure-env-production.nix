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

    users = {
      users.live-production = {
        description     = "cardano live-production";
        group           = "live-production";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devOpsKeys;
      };
      groups.live-production = {};
    };

    services.tarsnap = {
      enable = true;
      keyfile = "/var/lib/keys/tarsnap";
      archives.cardano-deployer = {
        directories = [
          "/home/live-production/.ec2-keys"
          "/home/live-production/.aws"
          "/home/live-production/.nixops"
          "/etc/"
        ];
      };
    };

    deployment.ec2.elasticIPv4 = resources.elasticIPs.cardanod-ip;
  };
}
