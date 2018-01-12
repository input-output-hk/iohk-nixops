{ IOHKaccessKeyId, ... }:

with (import ./../lib.nix);
let region = "eu-central-1";
    accessKeyId = IOHKaccessKeyId;
in {
  network.description = "IOHK infrastructure staging";

  hydra = { config, pkgs, resources, ... }: {

    imports = [
      ./../modules/papertrail.nix
      ./../modules/datadog.nix
    ];

    ## 
    security.acme.certs = mkForce {};
    services.nginx.enable = mkForce false;

    services.dd-agent.tags = ["env:staging" "depl:${config.deployment.name}"];

    deployment.ec2.elasticIPv4 = resources.elasticIPs.hydra-ip;

    deployment.route53.accessKeyId = config.deployment.ec2.accessKeyId;
    deployment.route53.hostName = "hydra.awstest2.iohkdev.io";
  };

  cardano-deployer = { config, pkgs, resources, ... }: {
    imports = [
      ./../modules/datadog.nix
      ./../modules/papertrail.nix
    ];

    services.dd-agent.tags = ["env:staging" "depl:${config.deployment.name}"];

    deployment.keys.tarsnap = {
      keyFile = ./../static/tarsnap-cardano-deployer.secret;
      destDir = "/var/lib/keys";
    };

    users = {
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
          "/home/staging/.ec2-keys"
          "/home/staging/.aws"
          "/home/staging/.nixops"
          "/etc/"
        ];
      };
    };

    deployment.ec2.elasticIPv4 = resources.elasticIPs.cardanod-ip;
  };
}
