{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodes = import ./cardano-nodes-config.nix { inherit accessKeyId; };
  nodeProdConf = import ./../modules/cardano-node-prod.nix;
in {
  resources = {
    elasticIPs = mkNodeIPs nodes accessKeyId;
    datadogMonitors = (with (import ./../modules/datadog-monitors.nix); {
      cpu = mkMonitor cpu_monitor;
      disk = mkMonitor disk_monitor;
      ram = mkMonitor ram_monitor;
      ntp = mkMonitor ntp_monitor;
      cardano_node_process = mkMonitor cardano_node_process_monitor;
    });
  };
} // (mkNodesUsing (params: nodeProdConf) nodes)
