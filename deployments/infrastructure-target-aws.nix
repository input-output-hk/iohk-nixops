{ deployerIP, IOHKaccessKeyId, ... }:

with (import ../lib.nix);
let org = "IOHK";
    region = "eu-central-1";
    accessKeyId = IOHKaccessKeyId;
in rec {
  hydra = { config, pkgs, resources, ... }: {
    imports = [
      ../modules/amazon-base.nix
    ];

    deployment.ec2 = {
      inherit accessKeyId;
      instanceType = mkForce "r3.2xlarge";
      ebsInitialRootDiskSize = mkForce 200;
      associatePublicIpAddress = true;
      securityGroups = [
        resources.ec2SecurityGroups."allow-deployer-ssh-${region}-${org}"
        resources.ec2SecurityGroups."allow-hydra-ssh-${region}-${org}"
        resources.ec2SecurityGroups."allow-public-www-https-${region}-${org}"
        resources.ec2SecurityGroups."allow-public-www-http-${region}-${org}"
      ];
    };
  };
  mantis-hydra = { config, pkgs, resources, ... }: {
    # See infrastructure-env-production.nix for description.
    imports = [
      ../modules/amazon-base.nix
    ];

    deployment.ec2 = {
      inherit accessKeyId;
      instanceType = mkForce "r3.2xlarge";
      ebsInitialRootDiskSize = mkForce 200;
      associatePublicIpAddress = true;
      securityGroups = [
        resources.ec2SecurityGroups."allow-deployer-ssh-${region}-${org}"
        resources.ec2SecurityGroups."allow-hydra-ssh-${region}-${org}"
        resources.ec2SecurityGroups."allow-public-www-https-${region}-${org}"
        resources.ec2SecurityGroups."allow-public-www-http-${region}-${org}"
      ];
    };
  };

  hydra-build-slave-1 = hydra;
  hydra-build-slave-2 = hydra;
  hydra-build-slave-3 = hydra;
  hydra-build-slave-4 = hydra;

  buildkite-agent-1   = hydra;
  buildkite-agent-2   = hydra;
  buildkite-agent-3   = hydra;
  buildkite-agent-4   = hydra;

  cardano-deployer = { config, pkgs, resources, ... }: {
    imports = [
      ../modules/amazon-base.nix
    ];

    deployment.ec2 = {
      inherit accessKeyId;
      instanceType = mkForce "r3.2xlarge";
      ebsInitialRootDiskSize = mkForce 50;
      associatePublicIpAddress = true;
      securityGroups = [
        resources.ec2SecurityGroups."allow-all-ssh-${region}-${org}"
      ];
    };
  };

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
      "allow-hydra-ssh-${region}-${org}" = { resources, ...}: {
        inherit region accessKeyId;
        description = "SSH";
        rules = [{
          protocol = "tcp"; # TCP
          fromPort = 22; toPort = 22;
          sourceIp = resources.elasticIPs.hydra-ip;
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
      "allow-public-www-https-${region}-${org}" = {
        inherit region accessKeyId;
        description = "WWW-https";
        rules = [{
          protocol = "tcp"; # TCP
          fromPort = 443; toPort = 443;
          sourceIp = "0.0.0.0/0";
        }];
      };
      "allow-public-www-http-${region}-${org}" = {
        inherit region accessKeyId;
        description = "WWW-http";
        rules = [{
          protocol = "tcp"; # TCP
          fromPort = 80; toPort = 80;
          sourceIp = "0.0.0.0/0";
        }];
      };
    };
    elasticIPs = {
      hydra-ip        = { inherit region accessKeyId; };
      mantis-hydra-ip = { inherit region accessKeyId; };
      cardanod-ip     = { inherit region accessKeyId; };
    };
    datadogMonitors = (with (import ../modules/datadog-monitors.nix); {
      disk       = mkMonitor (disk_monitor "!group:hydra-and-slaves" "0.8"  "0.9");
      disk_hydra = mkMonitor (disk_monitor  "group:hydra-and-slaves" "0.95" "0.951");
      ntp  = mkMonitor ntp_monitor;
    });
  };
}
