{ globals, ... }: with import ../lib.nix;
let nodeMap = { inherit (globals.fullMap) report-server; }; in

{
  require = [ ./report-server-bucket-storage.nix ];
  report-server = { config, resources, ...}: {
    imports = [
      ../modules/production.nix
      ../modules/datadog.nix
      ../modules/papertrail.nix
    ];

    services.report-server.zendesk = {
      accountName = "iohk";
      email = "daedalus-bug-reports@iohk.io";
      tokenFile = "/var/lib/keys/zendesk-token";
    };
  };

  resources.elasticIPs = nodesElasticIPs nodeMap;
  resources.datadogMonitors = with import ../modules/datadog-monitors.nix; {
    cardano_report_proccess = mkMonitor (recursiveUpdate cardano_report_process_monitor {
      monitorOptions.thresholds = {
        warning = 3;
        critical = 4;
        ok = 1;
      };
    });
  };
}
