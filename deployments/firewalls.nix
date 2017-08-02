{ accessKeyId, ... }:

with (import ./../lib.nix);
{
  resources.ec2SecurityGroups =
    let config   = (import ./cardano-nodes-config.nix { inherit accessKeyId; });
        sgs      = flip map config.securityGroupNames
                   (name: { name  = name;
                            value = { resources, ... }: (config.securityGroups resources.elasticIPs)."${name}"; });
    in listToAttrs sgs;
}
