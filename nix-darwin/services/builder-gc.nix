{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.nix.builder-gc;
in

{
  options = {
    nix.builder-gc.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically run the garbage collector when free disk space
        falls below a certain level.
      '';
    };

    nix.builder-gc.interval = mkOption {
      type = types.listOf types.attrs;
      default = map (m: { Minute = m; }) [ 0 15 30 45 ];
      description = "The time interval at which the garbage collector will run.";
    };

    nix.builder-gc.maxFreedMB = mkOption {
      type = types.int;
      example = 25 * 1024;
      description = ''
        Approximate maximum amount in megabytes to delete.
        This is given as the <filename>nix-collect-garbage --max-freed</filename>
        argument when the garbage collector is run automatically.
      '';
    };

    nix.builder-gc.minFreeMB = mkOption {
      type = types.int;
      example = 1024;
      description = ''
        Low disk level in megabytes which triggers garbage collection.
      '';
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons.nix-builder-gc = {
      script = ''
        free=$(${pkgs.coreutils}/bin/df --block-size=M --output=avail /nix/store | tail -n1 | sed s/M//)
        echo "Automatic GC: ''${free}M available"
        if [ $free -lt ${toString cfg.minFreeMB} ]; then
          ${config.nix.package}/bin/nix-collect-garbage --max-freed ${toString (cfg.maxFreedMB * 1024 * 1024)}
        fi
      '';
      environment.NIX_REMOTE = lib.optionalString config.services.nix-daemon.enable "daemon";
      serviceConfig.RunAtLoad = false;
      serviceConfig.StartCalendarInterval = cfg.interval;
    };
  };
}
