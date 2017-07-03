{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeProdConf = import ./../modules/cardano-node-prod.nix;
in {
  sl-explorer  = nodeProdConf // {
    deployment = nodeProdConf.deployment // {
      route53  = nodeProdConf.deployment.route53 // {
        accessKeyId = config.deployment.ec2.accessKeyId;
        hostName    = "cardano-explorer.aws.iohk.io";
      };
    };
  };

  resources = {
    elasticIPs = {
      nodeip40 = { inherit region accessKeyId; };
    };
  };
}
