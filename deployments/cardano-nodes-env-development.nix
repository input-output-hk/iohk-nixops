{ globals, ... }: with (import ./../lib.nix);



(flip mapAttrs globals.nodeMap (name: import ./../modules/cardano-development.nix))
// {
  network.description = "Cardano Development";

  resources.ec2SecurityGroups =
    listToAttrs (flip map globals.orgXRegions
                 ({ org, region }:
                  nameValuePair "allow-all-${region}-${org}"
                                { inherit region;
                                  accessKeyId = globals.orgAccessKeys.${org};
                                  description = "Allow all ${org}/${region}";
                                  rules = [{
                                    protocol = "-1"; # Any
                                    sourceIp = "0.0.0.0/0";
                                    fromPort = 0; toPort = 65535;
                                  }];
                                }));
}
