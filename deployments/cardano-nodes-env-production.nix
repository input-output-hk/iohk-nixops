{ globals, ... }: with import ../lib.nix;
let nodeMap = globals.nodeMap; in


(flip mapAttrs nodeMap (name: import ../modules/cardano-production.nix))
// {
  network.description = "Mainnet";

  resources = {
    elasticIPs = nodesElasticIPs nodeMap;
    datadogMonitors = with import ../modules/datadog-monitors.nix; {
      cpu = mkMonitor cpu_monitor;
      disk = mkMonitor (disk_monitor "!host:mainnet.ec2.report-server" "0.8" "0.9");
      inodes = mkMonitor (inodes_monitor 7 2);
      ram = mkMonitor ram_monitor;
      ntp = mkMonitor ntp_monitor;
      cardano_node_simple_process = mkMonitor cardano_node_simple_process_monitor;
      chain_quality = mkMonitor chain_quality_monitor;
      mem_pool_size = mkMonitor mem_pool_size_monitor;
    };
  };
}
