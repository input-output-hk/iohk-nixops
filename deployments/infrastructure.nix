{ ... }:

with (import ./../lib.nix);
let
  iohk-pkgs = import ../default.nix {};
  mkHydraBuildSlave = { config, name, pkgs, ... }: {
    imports = [
      ./../modules/common.nix
      ./../modules/hydra-slave.nix
    ];
  };
  mkBuildkiteAgent = { ... }: {
    imports = [
      ./../modules/common.nix
      ./../modules/buildkite-agent.nix
    ];
  };
in {
  require = [ ./ugly-fix.nix ];
  hydra = { config, pkgs, ... }: {
    # On first setup:

    # Locally: $ ssh-keygen -C "hydra@hydra.example.org" -N "" -f static/id_buildfarm
    # On Hydra: $ /run/current-system/sw/bin/hydra-create-user alice --full-name 'Alice Q. User' --email-address 'alice@example.org' --password foobar --role admin

    imports = [
      ./../modules/common.nix
      ./../modules/hydra-slave.nix
      ./../modules/hydra-master.nix
    ];
  };

  hydra-build-slave-1 = mkHydraBuildSlave;
  hydra-build-slave-2 = mkHydraBuildSlave;

  buildkite-agent-1   = mkBuildkiteAgent;
  buildkite-agent-2   = mkBuildkiteAgent;

  cardano-deployer = { config, pkgs, ... }: {
    imports = [
      ./../modules/common.nix
    ];

    environment.systemPackages = [ iohk-pkgs.iohk-ops ];

    networking.firewall.allowedTCPPortRanges = [
      { from = 24962; to = 25062; }
    ];
  };
  resources = {
    datadogMonitors = (with (import ./../modules/datadog-monitors.nix); {
      disk = mkMonitor disk_monitor;
      ntp = mkMonitor ntp_monitor;
    });
  };
}
