with import ../lib.nix;

rec {
  alertMessage = msg: ''
    {{#is_alert}}
    ${msg}
    {{/is_alert}}
  '';
  warningMessage = msg: ''
    {{#is_warning}}
    ${msg}
    {{/is_warning}}
  '';
  noDataMessage = msg: ''
    {{#is_no_data}}
    ${msg}
    {{/is_no_data}}
  '';
  pagerDutyCritical = "@pagerduty-Datadog_Critical";
  pagerDutyNonCritical = "@pagerduty-Datadog_Non-Critical";
  pagerDutyPolicy = {
    normal = ''
      ${alertMessage pagerDutyCritical}
      ${warningMessage pagerDutyNonCritical}
      ${noDataMessage pagerDutyCritical}
    '';
    nonCritical = ''
      ${alertMessage pagerDutyNonCritical}
      ${warningMessage pagerDutyNonCritical}
      ${noDataMessage pagerDutyNonCritical}
    '';
  };

  baseMonitor = {
    apiKey = fileContents ./../static/datadog-api.secret;
    appKey = fileContents ./../static/datadog-application.secret;
    monitorOptions = {
      renotify_interval = 10;
      include_tags = true;
      no_data_timeframe = 10;
      notify_audit = true;
      notify_no_data = false;
      require_full_window = true;
      new_host_delay = 120;
    };
  };

  mkMonitor = { name, type, query, message ? pagerDutyPolicy.normal, monitorOptions ? {} }:
    { config, ... }:
    baseMonitor // {
      inherit type message;
      name = "${config.deployment.name}: ${name}";
      query = query config;
      monitorOptions = builtins.toJSON (baseMonitor.monitorOptions // monitorOptions);
    };

  # Common monitors
  cpu_monitor = {
    name = "High CPU usage";
    type = "metric alert";
    query = config: "avg(last_5m):avg:system.load.norm.1{depl:${config.deployment.name},!host:iohk-infra.ec2.cardano-deployer,!host:iohk-infra.ec2.hydra,!host:iohk-infra.ec2.hydra-mantis} by {host} > 1.1";
    monitorOptions.thresholds = {
      warning = "1";
      critical = "1.1";
    };
  };

  disk_monitor = scope_restriction: warning: critical: {
    name = "High disk usage";
    type = "metric alert";
    query = config: "max(last_5m):avg:system.disk.in_use{depl:${config.deployment.name},${scope_restriction}} by {host,device} > ${critical}";
    monitorOptions.thresholds = {
      warning = "${warning}";
      critical = "${critical}";
    };
  };

  inodes_monitor = warningDays: criticalDays: let
    inodes = days: 2160 * 2 * 2 * days;  # 2 files per block, 24 hours of blocks.
    warning = inodes warningDays;
    critical = inodes criticalDays;
  in {
    name = "Low available inodes";
    type = "metric alert";
    query = config: "min(last_1m):avg:system.fs.inodes.free{depl:${config.deployment.name}} by {host,device} < ${toString critical}";
    monitorOptions.thresholds = {
      inherit warning critical;
    };
  };

  ram_monitor = {
    name = "RAM is running low";
    type = "metric alert";
    query = config: "avg(last_1m):avg:system.mem.pct_usable{depl:${config.deployment.name}} by {host} < 0.2";
    monitorOptions.thresholds = {
      warning = "0.5";
      critical = "0.2";
    };
  };

  ntp_monitor = {
    name = "Clock out of sync with NTP";
    type = "service check";
    query = config: "\"ntp.in_sync\".over(\"depl:${config.deployment.name}\").by(\"host\").last(2).count_by_status()";
    monitorOptions.thresholds = {
      critical = 1;
    };
  };

  cardano_node_simple_process_monitor = {
    name = "cardano-node-simple process is down";
    type = "service check";
    query = config: "\"process.up\".over(\"depl:${config.deployment.name}\",\"process:cardano-node-simple\").exclude(\"host:mainnet.ec2.explorer\").by(\"host\",\"process\").last(5).count_by_status()";
    monitorOptions = {
      notify_no_data = true;
      no_data_timeframe = 10;
      thresholds = {
        warning = 2;
        critical = 4;
        ok = 2;
      };
    };
  };

  cardano_explorer_process_monitor = {
    name = "cardano-explorer process is down";
    type = "service check";
    query = config: "\"process.up\".over(\"depl:${config.deployment.name}\",\"process:cardano-explorer\").by(\"host\",\"process\").last(6).count_by_status()";
    monitorOptions = {
      notify_no_data = true;
      no_data_timeframe = 10;
      thresholds = {
        warning = 4;
        critical = 5;
        ok = 2;
      };
    };
  };

  cardano_report_process_monitor = {
    name = "cardano-report-server process is down";
    type = "service check";
    query = config: "\"process.up\".over(\"depl:${config.deployment.name}\",\"process:cardano-report-server\").by(\"host\",\"process\").last(6).count_by_status()";
    monitorOptions = {
      notify_no_data = true;
      no_data_timeframe = 10;
      thresholds = {
        warning = 4;
        critical = 5;
        ok = 2;
      };
    };
  };

  cardano_faucet_process_monitor = {
    name = "cardano-faucet process is down";
    type = "service check";
    query = config: "\"process.up\".over(\"depl:${config.deployment.name}\",\"process:cardano-faucet\").by(\"host\",\"process\").last(6).count_by_status()";
    monitorOptions.thresholds = {
      warning = 4;
      critical = 5;
      ok = 2;
    };
  };

  chain_quality_monitor = {
    name = "Degraded Chain Quality over last 2160 blocks";
    type = "metric alert";
    query = config: "max(last_5m):avg:cardano.chain_quality_last_k_2160_blocks{depl:${config.deployment.name}} by {host} < 99";
    monitorOptions = {
      notify_no_data = true;
      no_data_timeframe = 5;
      thresholds = {
        warning = "99.3";
        critical = "99";
      };
    };
  };

  mem_pool_size_monitor = {
    name = "MemPoolSize tx count is larger than expected";
    type = "metric alert";
    query = config: "max(last_5m):avg:cardano.MemPoolSize{depl:${config.deployment.name}} by {host} > 190";
    message = "When a node's MemPoolSize grows larger than the system can handle, transactions will be dropped. The actual thresholds for that in mainnet are unknown, but [based on benchmarks done beforehand](https://input-output-rnd.slack.com/archives/C2VJ41WDP/p1506563332000201) transactions started getting dropped when the MemPoolSize was ~200 txs.\n\n${pagerDutyPolicy.normal}";
    monitorOptions = {
      notify_no_data = true;
      no_data_timeframe = 10;
      thresholds = {
        critical = 190;
        warning = 180;
      };
    };
  };
}
