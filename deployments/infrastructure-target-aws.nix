{ deployerIP, IOHKaccessKeyId, ... }:

with (import ./../lib.nix);
let org = "IOHK";
    region = "eu-central-1";
    accessKeyId = IOHKaccessKeyId;
    generic-infra-host =
      { ebsInitialRootDiskSize
      , allowJumphostSSH ? true
      , allowPublicSSH ? false
      , allowPublicWWW ? false
       }:
        { config, pkgs, resources, ... }: {
          imports = [
            ./../modules/amazon-base.nix
          ];

          deployment.ec2 = {
            inherit accessKeyId;
            instanceType = mkForce "r3.2xlarge";
            ebsInitialRootDiskSize = mkForce ebsInitialRootDiskSize;
            associatePublicIpAddress = true;
            securityGroups =
              optionals allowJumphostSSH [ resources.ec2SecurityGroups."allow-deployer-ssh-${region}-${org}" ] ++
              optionals allowPublicSSH   [ resources.ec2SecurityGroups."allow-all-ssh-${region}-${org}"      ] ++
              optionals allowPublicWWW   [ resources.ec2SecurityGroups."allow-public-www-${region}-${org}"   ];
          };
        };
in rec {
  hydra               = generic-infra-host { ebsInitialRootDiskSize = 200; allowPublicWWW = true; };
  hydra-build-slave-1 = generic-infra-host { ebsInitialRootDiskSize = 200; allowPublicWWW = true; };
  hydra-build-slave-2 = generic-infra-host { ebsInitialRootDiskSize = 200; allowPublicWWW = true; };
  cardano-deployer    = generic-infra-host { ebsInitialRootDiskSize = 50;  allowPublicSSH = true; allowJumphostSSH = false; };

  resources = {
    ec2SecurityGroups = {
      "allow-deployer-ssh-${region}-${org}" = {
        inherit region accessKeyId;
        description = "SSH";
        rules = [{
          protocol = "tcp"; # TCP
          fromPort = 22; toPort = 22;
          sourceIp = deployerIP + "/32";
        }];
      };
      "allow-all-ssh-${region}-${org}" = {
        inherit region accessKeyId;
        description = "SSH";
        rules = [{
          protocol = "tcp"; # TCP
          fromPort = 22; toPort = 22;
          sourceIp = "0.0.0.0/0";
        }];
      };
      "allow-public-www-${region}-${org}" = {
        inherit region accessKeyId;
        description = "WWW";
        rules = [{
          protocol = "tcp"; # TCP
          fromPort = 443; toPort = 443;
          sourceIp = "0.0.0.0/0";
        }];
      };
    };
  };
}
