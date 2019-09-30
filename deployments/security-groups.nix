## This file contains most of the security group definitions, but not all.
##
## Remaining ones are:
##  - 'allow-all-*' for the development environment

{ globals, ... }:

with import ../lib.nix;
{
  require = [ ./security-groups/allow-deployer-ssh.nix ];
  resources.ec2SecurityGroups =
    let sgs               = flip map securityGroupNames
                            (name: { name = name;
                                    value = { config, resources, nodes, ... }: (eIPsSecurityGroups { inherit config resources nodes; })."${name}"; });
        securityGroupNames =
          (             (centralRegionSGNames  centralRegion)
          ++  concatMap  regionSGNames         globals.allRegions
          ++  concatMap  orgXRegionSGNames     globals.orgXRegions
          ++  concatMap  coreSGNames           globals.cores
          ++  concatMap  monitorSGNames        [ globals.monitoringNV ]
          );
        eIPsSecurityGroups = { config, resources, nodes }:
          (fold (x: y: x // y) {}
          (         (centralRegionSGs  centralRegion)

           ++  map  (regionSGs         { nodePort = 3000; nodePortEnd = 3001; }) # TODO: 'config' is mostly empty here.
                    globals.allRegions

           ++  map  (orgXRegionSGs { inherit (globals) monitoringNV; inherit nodes; } resources.elasticIPs)
                    globals.orgXRegions

           ++  map  (coreSGs resources.elasticIPs) # TODO: config for port
                    globals.cores

           ++  map  (monitorSGs { inherit config nodes; } { nodePort = 5044; } resources.elasticIPs)
                    [ globals.monitoringNV ]
          ));
        accessKeyId = globals.orgAccessKeys.IOHK; # Design decision with regard to AWS SGs.
        ##
        ## SG names and definitions
        ##
        regionSGNames = region:
            [ "allow-kademlia-public-udp-${region}"
              "allow-cardano-public-tcp-${region}"
              "allow-jormangandr-public-tcp-${region}"
            ];
        regionSGs      = { nodePort, nodePortEnd }: region: {
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
              rules = [
                {
                protocol = "tcp"; # TCP
                fromPort = nodePort; toPort = nodePortEnd;
                sourceIp = "0.0.0.0/0";
                }
              ];
            };
            "allow-jormangandr-public-tcp-${region}" = {
              inherit region accessKeyId;
              description = "Jormangandr TCP public";
              rules = [
                {
                protocol = "tcp"; # TCP
                fromPort = nodePort; toPort = nodePort;
                sourceIp = "0.0.0.0/0";
                }
              ];
            };
          };
        orgXRegionSGNames = { org, region }:
            [ "allow-ekg-public-tcp-${region}-${org}"
            ];
        orgXRegionSGs     = { monitoringNV, nodes }: ips: { org, region }: {
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
        monitorSGNames = monitoringNV:
            [ "allow-monitoring-static-peers-${monitoringNV.value.region}-${monitoringNV.value.org}" ];
        monitorSGs     = { config, nodes }: { nodePort }: ips: monitoringNV:
          let
            neighbourNames =
              let
                monitorPeers = builtins.attrNames nodes;
                getIP = nodeName: ips."${nodeName}-ip" or null;
                neighborIPs = builtins.filter (ip: ip != null) (map getIP monitorPeers);
              in  traceF (p: "${monitoringNV.name} peers: " + concatStringsSep ", " monitorPeers) neighborIPs;
            neighGrant = ip:
              {
                  fromPort = nodePort; toPort = nodePort; # graylog journalbeat input = TCP port 5044
                  sourceIp = ip;
              };
          in {
            "allow-monitoring-static-peers-${monitoringNV.value.region}-${monitoringNV.value.org}" = {
              _file = ./security-groups.nix;
              inherit (monitoringNV.value) accessKeyId region;
              description = "Monitoring TCP static peers of ${monitoringNV.name}";
              rules = if nodes ? "${monitoringNV.name}" then (map neighGrant neighbourNames) else [];
            };
          };
        coreSGNames = core:
            [ "allow-cardano-static-peers-${core.name}-${core.value.region}-${core.value.org}" ];
        coreSGs     = ips: core:
          let neighbourNames = traceF (p: "${core.name} peers: " + concatStringsSep ", " core.value.peers) core.value.peers;
              neighbours = map (name: globals.fullMap.${name}) neighbourNames;
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
            ];
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
          }];
    in listToAttrs sgs;
}
