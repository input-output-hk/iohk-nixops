{ accessKeyId }:

with (import ./../lib.nix);

params:
  { config, resources, pkgs, nodes, options, ... }:
    let
      indexPlus1 = params.i + 1; # used for keys
      cfg = config.services.cardano-node;
      cardanoNodeConfigs = filter (c: c.services.cardano-node.enable)
               (map (node: node.config) (attrValues nodes));

      sgByName = x: resources.ec2SecurityGroups.${x};
      sgNames  = if   config.services.cardano-node.enable == false
                 then [ "allow-open-${params.region}" ]
                 else params.sg-names;
      sgs      = map sgByName sgNames;
    in  {
      imports = [
        ./amazon-base.nix
      ];

      services.cardano-node = {
        initialKademliaPeers = genPeersFromConfig (
          if (cfg.enableP2P && !cfg.productionMode)
          then [(head cardanoNodeConfigs)]
          else cardanoNodeConfigs
        );
        publicIP = if options.networking.publicIPv4.isDefined then config.networking.publicIPv4 else null;
        privateIP = if options.networking.privateIPv4.isDefined then config.networking.privateIPv4 else "0.0.0.0";
        statsdServer = "127.0.0.1:8125";
      };

      # TODO: DEVOPS-8
      #deployment.ec2.ami = (import ./amis.nix).${config.deployment.ec2.region};
      deployment.ec2.region = mkForce params.region;
      deployment.ec2.accessKeyId = accessKeyId;
      deployment.ec2.keyPair = resources.ec2KeyPairs.${keypairFor accessKeyId params.region};
      deployment.ec2.securityGroups = mkForce sgs;
      deployment.keys = (optionalAttrs (cfg.productionMode && !cfg.hasExplorer) {
        "key${toString indexPlus1}" = {
          keyFile = ./. + "/../keys/key${toString indexPlus1}.sk";
          user = "cardano-node";
        };
      }) // optionalAttrs (config.services.cardano-node.enable) {
        "cluster.yaml" = {
          keyFile = ./. + "/../cluster.yaml";
          user = "cardano-node";
        };
      };
    }
