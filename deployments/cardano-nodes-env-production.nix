{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeArgs    = (import ./cardano-nodes-config.nix { inherit accessKeyId; }).nodeArgs;
  nodeEnvConf = import ./../modules/cardano-node-prod.nix;
in
{
  resources = {
    elasticIPs = mkNodeIPs nodeArgs accessKeyId;
    datadogMonitors = (with (import ./../modules/datadog-monitors.nix); {
      cpu = mkMonitor cpu_monitor;
      disk = mkMonitor disk_monitor;
      ram = mkMonitor ram_monitor;
      ntp = mkMonitor ntp_monitor;
      cardano_node_process = mkMonitor cardano_node_process_monitor;
    });
  };
} // (mkNodesUsing (params: nodeEnvConf) nodeArgs)
