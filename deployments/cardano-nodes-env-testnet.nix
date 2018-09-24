{ globals, ... }: with import ../lib.nix;
let nodeMap = globals.nodeMap; in


(flip mapAttrs nodeMap (name: import ../modules/cardano-testnet.nix))
// {
  network.description = "Cardano Testnet";

  resources = {
    elasticIPs = nodesElasticIPs nodeMap;
    datadogMonitors = with import ../modules/datadog-monitors.nix; {
      cpu = mkMonitor (cpu_monitor // {
        message = pagerDutyPolicy.nonCritical;
        query = config: "avg(last_5m):avg:system.load.norm.1{depl:${config.deployment.name}} by {host} > 0.99";
        monitorOptions.thresholds = {
          warning = "0.98";
          critical = "0.99";
        };
      });

      disk = mkMonitor (disk_monitor "!host:rc-staging.ec2.report-server" "0.8" "0.9" // {
        message = pagerDutyPolicy.nonCritical;
      });
      inodes = mkMonitor ((inodes_monitor 7 2) // {
        message = pagerDutyPolicy.nonCritical;
      });
      ram = mkMonitor (ram_monitor // {
        message = pagerDutyPolicy.nonCritical;
      });
      ntp = mkMonitor (ntp_monitor // {
        message = pagerDutyPolicy.nonCritical;
      });

      cardano_node_simple_process = mkMonitor (cardano_node_simple_process_monitor // {
        message = pagerDutyPolicy.nonCritical;
        monitorOptions.thresholds = {
          warning = 3;
          critical = 4;
          ok = 1;
        };
      });

      chain_quality = mkMonitor chain_quality_monitor;
      mem_pool_size = mkMonitor mem_pool_size_monitor;
    };
  };
}
