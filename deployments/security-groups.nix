## This file contains most of the security group definitions, but not all.
##
## Remaining ones are:
##  - 'allow-all-*' for the development environment
##  - 'allow-deployer-ssh-*' for the infrastructure

{ globals, ... }:

with import ../lib.nix;
{
  resources.ec2SecurityGroups =
    let sgs               = flip map securityGroupNames
                            (name: { name = name;
                                    value = { config, resources, ... }: (eIPsSecurityGroups { inherit config resources; })."${name}"; });
        securityGroupNames =
         (              (centralRegionSGNames  centralRegion)
          ++  concatMap  regionSGNames         globals.allRegions
          ++  concatMap  orgXRegionSGNames     globals.orgXRegions
          ++  concatMap  coreSGNames           globals.cores
         );
        eIPsSecurityGroups = { config, resources }:
          (fold (x: y: x // y) {}
          (         (centralRegionSGs  centralRegion)

           ++  map  (regionSGs         { nodePort = 3000; }) # TODO: 'config' is mostly empty here.
                    globals.allRegions

           ++  map  (orgXRegionSGs)
                    globals.orgXRegions

           ++  map  (coreSGs           3000 resources.elasticIPs) # TODO: config for port
                    globals.cores
          ));
        accessKeyId   = globals.orgAccessKeys.IOHK; # Design decision with regard to AWS SGs.
        ##
        ## SG names and definitions
        ##
        regionSGNames = region:
            [ "allow-kademlia-public-udp-${region}"
              "allow-cardano-public-tcp-${region}"
            ];
        regionSGs      = { nodePort }: region: {
            "allow-kademlia-public-udp-${region}" = {
              inherit region accessKeyId;
              description = "Kademlia UDP public";
              rules = [{
                protocol = "udp"; # UDP
                sourceIp = "0.0.0.0/0";
                fromPort = 1024; toPort = 65535;
              }];
            };
            "allow-cardano-public-tcp-${region}" = {
              inherit region accessKeyId;
              description = "Cardano TCP public";
              rules = [{
                protocol = "tcp"; # TCP
                fromPort = nodePort; toPort = nodePort;
                sourceIp = "0.0.0.0/0";
              }];
            };
          };
        orgXRegionSGNames = { org, region }:
            [ "allow-deployer-ssh-${region}-${org}"
              "allow-ekg-public-tcp-${region}-${org}"
            ];
        orgXRegionSGs     = { org, region}: {
            "allow-deployer-ssh-${region}-${org}" = {
              inherit region;
              accessKeyId = globals.orgAccessKeys.${org};
              description = "SSH";
              rules = [{
                protocol = "tcp"; # TCP
                fromPort = 22; toPort = 22;
                sourceIp = globals.deployerIP + "/32";
              }];
            };
            "allow-ekg-public-tcp-${region}-${org}" = {
              inherit region;
              accessKeyId = globals.orgAccessKeys.${org};
              description = "EKG 8080 public";
              rules = [{
                protocol = "tcp";
                fromPort = 8080; toPort = 8080;
                sourceIp = "0.0.0.0/0";
              }];
            };
          };
        coreSGNames = core:
            [ "allow-cardano-static-peers-${core.name}-${core.value.region}-${core.value.org}" ];
        coreSGs     = nodePort: ips: core:
          let neighbourNames = traceF (p: "${core.name} peers: " + concatStringsSep ", " core.value.peers) core.value.peers;
              neighbours = map (name: globals.nodeMap.${name}) neighbourNames;
              neighGrant =
              neigh:
              let ip = ips."${toString neigh.name}-ip";
              in {
                  fromPort = core.value.port; toPort = core.value.port;
                  sourceIp = ip;
              };
          in {
            "allow-cardano-static-peers-${core.name}-${core.value.region}-${core.value.org}" = {
              inherit (core.value) accessKeyId region;
              description = "Cardano TCP static peers of ${core.name}";
              rules = map neighGrant neighbours;
            };
          };
        centralRegionSGNames = centralRegion:
            [ "allow-to-explorer-${centralRegion}"
              "allow-to-faucet-${centralRegion}"
              "allow-to-report-server-${centralRegion}" ];
        centralRegionSGs = centralRegion:
          let region = centralRegion;
          in [{
            "allow-to-explorer-${region}" = {
              inherit region accessKeyId;
              description = "Access Cardano Explorer";
              rules = [{
                protocol = "tcp";
                fromPort = 80; toPort = 80;
                sourceIp = "0.0.0.0/0";
              } {
                protocol = "tcp";
                fromPort = 443; toPort = 443;
                sourceIp = "0.0.0.0/0";
              }];
            };
            "allow-to-faucet-${region}" = {
              inherit region accessKeyId;
              description = "Access Cardano Faucet";
              rules = [{
                protocol = "tcp";
                fromPort = 80; toPort = 80;
                sourceIp = "0.0.0.0/0";
              } {
                protocol = "tcp";
                fromPort = 443; toPort = 443;
                sourceIp = "0.0.0.0/0";
              }];
            };
            "allow-to-report-server-${region}" = {
              inherit region accessKeyId;
              description = "Access Cardano report server";
              rules = [{
                protocol = "tcp";
                fromPort = 8080; toPort = 8080;
                sourceIp = "0.0.0.0/0";
              }];
            };
          }];
    in listToAttrs sgs;
}
