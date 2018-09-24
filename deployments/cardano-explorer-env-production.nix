{ globals, ... }: with import ../lib.nix;
let nodeMap = { inherit (globals.fullMap) explorer; }; in


{
  explorer = (import ../modules/cardano-production.nix) nodeMap.explorer;
  resources = {
    elasticIPs = nodesElasticIPs nodeMap;
    datadogMonitors = with import ../modules/datadog-monitors.nix; {
      cardano_explorer_process = mkMonitor (recursiveUpdate cardano_explorer_process_monitor {
        monitorOptions.thresholds = {
          warning = 3;
          critical = 4;
          ok = 1;
        };
      });
    };
  };
}
