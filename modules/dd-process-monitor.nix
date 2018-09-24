{ config, lib, ... }:

with lib;
let
  cfg = config.services.dd-agent;
in {
  options = {
    services.dd-agent.processMonitor = mkOption {
      type = types.nullOr types.string;
      default = null;
    };
  };
  config = mkIf (cfg.processMonitor != null) {
    services.dd-agent.processConfig = ''
      init_config:

      instances:
      - name : ${cfg.processMonitor}
        search_string: ['${cfg.processMonitor}']
        exact_match: True
        thresholds:
          critical: [1, 1]
    '';
  };
}
