{ lib, ... }:

with lib;

{
  options = {
    params = mkOption {
    };
    global = mkOption {
      description = "IOHK global option group.";
      default = {};
      type = with types; submodule {
        options = {
          allocateElasticIP = mkOption {
            type = bool;
            description = "Whether to allocate an Elastic IP to the node.";
            default = false;
          };
          centralRegion = mkOption {
            type = str;
            description = "Region for deployer, explorer, report-server and other global services.";
            default = "eu-central-1";
          };
          defaultOrg = mkOption {
            type = enum [ "CF" "IOHK" "Emurgo" ];
            description = "Organisation hosting deployer, report-server and other global services.";
            default = "IOHK";
          };
          organisation = mkOption {
            type = enum [ "CF" "IOHK" "Emurgo" ];
            description = "Organisation managing this machine.";
            default = "IOHK";
          };
          deployerIP = mkOption {
            type = str;
            description = "The IP address of the deployer.";
            default = null;
          };
          dnsHostname = mkOption {
            type = nullOr str;
            description = "The hostname part of FQDN to advertise via DNS.";
            default = null;
          };
          dnsDomainname = mkOption {
            type = nullOr str;
            description = "The domain part of FQDN to advertise via DNS.";
            default = null;
          };
          enableEkgWeb = mkOption {
            type = bool;
            description = "Whether to start/expose EKG web frontend.";
            default = false;
          };
          nRelays = mkOption {
            type = int;
            description = "COMPUTED FROM TOPOLOGY: total N of relays.";
          };
          omitDetailedSecurityGroups = mkOption {
            type = bool;
            description = "Whether to omit adding detailed security groups.  Relies on use of 'allow-all-*'.";
            default = false;
          };
          topologyYaml = mkOption {
            type = path;
            description = "DEPL-ARG PASSTHROUGH: topology file.";
          };
          environment = mkOption {
            type = string;
          };
          systemStart = mkOption {
            type = int;
          };
          nodeMap = mkOption {
          };
          relays = mkOption {
          };
        };
      };
    };
  };
}
