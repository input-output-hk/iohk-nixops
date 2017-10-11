{ ... }:

with (import ./../lib.nix);
let
  iohk-pkgs = import ../default.nix {};
  mkHydraBuildSlave = { config, pkgs, ... }: {
    imports = [
      ./../modules/common.nix
      ./../modules/hydra-slave.nix
    ];
  };
in {
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

  cardano-deployer = { config, pkgs, ... }: {
    imports = [
      ./../modules/common.nix
    ];

    environment.systemPackages = [ iohk-pkgs.iohk-ops ];

    users = {
      users.staging = {
        description     = "cardano staging";
        group           = "staging";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devKeys;
      };
      groups.staging = {};

      users.live-production = {
        description     = "cardano live-production";
        group           = "live-production";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devOpsKeys;
      };
      groups.live-production = {};
    };

    services.tarsnap = {
      enable = true;
      keyfile = "/var/lib/keys/tarsnap";
      archives.cardano-deployer = {
        directories = [
          "/home/staging/.ec2-keys"
          "/home/staging/.aws"
          "/home/staging/.nixops"
          "/home/live-production/.ec2-keys"
          "/home/live-production/.aws"
          "/home/live-production/.nixops"
          "/etc/"
        ];
      };
    };

    networking.firewall.allowedTCPPortRanges = [
      { from = 24962; to = 25062; }
    ];
  };
}
