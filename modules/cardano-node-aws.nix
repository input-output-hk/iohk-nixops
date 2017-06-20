with (import ./../lib.nix);

testIndex: region:
  { config, resources, pkgs, nodes, options, ... }:
    let
      cfg = config.services.cardano-node;
      cardanoNodeConfigs = filter (c: c.services.cardano-node.enable)
               (map (node: node.config) (attrValues nodes));
    in  {
      imports = [
        ./amazon-base.nix
      ];

      services.cardano-node = {
        initialPeers = genPeersFromConfig (
          if (cfg.enableP2P && !cfg.productionMode)
          then [head cardanoNodeConfigs]
          else cardanoNodeConfigs
        );
        publicIP = if options.networking.publicIPv4.isDefined then config.networking.publicIPv4 else null;
        privateIP = if options.networking.privateIPv4.isDefined then config.networking.privateIPv4 else "0.0.0.0";
        ekgSink = "127.0.0.1:8125";
      };

      # TODO: DEVOPS-8
      #deployment.ec2.ami = (import ./amis.nix).${config.deployment.ec2.region};
      deployment.ec2.region = region;
      deployment.ec2.keyPair = resources.ec2KeyPairs.${keypairFor region};
      deployment.keys = optionalAttrs (cfg.productionMode && !cfg.hasExplorer) {
        "key${toString (testIndex + 1)}" = {
          keyFile = ./. + "/../keys/key${toString (testIndex + 1)}.sk";
          user = "cardano-node";
        };
      };
    }
