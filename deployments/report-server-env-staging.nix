{ globals, ... }: with (import ./../lib.nix);
let nodeMap = { inherit (globals.fullMap) report-server; }; in

{
  require = [ ./report-server-bucket-storage.nix ];
  report-server = { config, resources, lib, ...}: {
    imports = [
      ../modules/staging.nix
      ../modules/datadog.nix
      ../modules/papertrail.nix
    ];

    services.report-server.zendesk = {
      accountName = "iohk1534436789";  # the sandbox on the main IOHK acct
      email = "staging-report-server@iohk.io";
      tokenFile = "/var/lib/keys/zendesk-token";
    };
    deployment.route53.hostName = lib.mkForce "staging-report-server.${config.global.dnsDomainname}";
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
