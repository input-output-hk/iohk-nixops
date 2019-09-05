{ ... }:

with (import ../lib.nix);

let
  iohk-pkgs = import ../default.nix {};

in {
  network.description = "Testnet Deployer";

  testnet-deployer = { config, pkgs, resources, ... }: {
    imports = [
      ../modules/common.nix
      ../modules/monitoring-exporters.nix
      ../modules/deployer-base.nix
    ];

    networking.hostName = "testnet-deployer";

    users.groups.developers = {};

    users.users = {
      # Deploy cardano-sl testnet
      testnet = {
        isNormalUser = true;
        description  = "Cardano SL Testnet NixOps Deployer";
        group        = "deployers";
        openssh.authorizedKeys.keys = devOpsKeys ++ testnetKeys;
      };

      # Deploy cardano-sl staging network
      staging = {
        description  = "Staging NixOps deployer";
        group        = "deployers";
        isNormalUser = true;
        openssh.authorizedKeys.keys = devOpsKeys;
      };

      # Deploy mantis (kevm/iele) testnet
      mantis-testnet = {
        isNormalUser = true;
        description  = "Mantis Testnet NixOps Deployer";
        group        = "deployers";
        openssh.authorizedKeys.keys = mantisOpsKeys;
      };

      # Deploy Hydra and agents
      infra = {
        description  = "CI NixOps deployer";
        group        = "deployers";
        isNormalUser = true;
        openssh.authorizedKeys.keys = devOpsKeys;
      };
    }
    # Normal users who can deploy developer clusters on AWS.
    // mapAttrs (name: keys: {
      group = "developers";
      isNormalUser = true;
      openssh.authorizedKeys.keys = keys;
    }) (csl-developers // devOps);

    environment.systemPackages = let
      usernames = attrNames (csl-developers // devOps);
      list-developers = pkgs.writeShellScriptBin "list-developers"
        (concatMapStringsSep "\n" (u: "echo ${u}") usernames);
    in [ list-developers ];

    deployment.keys.tarsnap = {
      keyFile = ./../static/tarsnap-testnet-deployer.secret;
      destDir = "/var/lib/keys";
    };

    services.tarsnap = {
      enable = true;
      keyfile = "/var/lib/keys/tarsnap";
      archives.testnet-deployer = {
        directories = [
          "/home"
          "/etc/"
        ];
      };
    };
  };
}
