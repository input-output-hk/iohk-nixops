{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeStagingConf = import ./../modules/cardano-node-staging.nix;
in {
  sl-explorer  = nodeStagingConf // {
    deployment = nodeStagingConf.deployment // {
      route53  = nodeStagingConf.deployment.route53 // {
        accessKeyId = config.deployment.ec2.accessKeyId;
        hostName    = "cardano-explorer.aws.iohkdev.io";
      };
    };
  };

  resources = {
    elasticIPs = {
      nodeip40 = { inherit region accessKeyId; };
    };
  };
}
