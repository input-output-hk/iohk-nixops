{ name, config, resources, ... }:

with (import ./../lib.nix);

{
 deployment.targetEnv = "ec2";
 deployment.ec2.instanceType = mkDefault "t2.large";
 deployment.ec2.region = mkDefault region;
 deployment.ec2.keyPair = mkDefault (resources.ec2KeyPairs.${keypairFor config.deployment.ec2.accessKeyId region});
 deployment.ec2.ebsInitialRootDiskSize = mkDefault 30;
 networking.hostName = "${config.deployment.name}.${config.deployment.targetEnv}.${name}";
}
