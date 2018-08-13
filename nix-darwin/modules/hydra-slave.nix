{ config, lib, pkgs, ... }:

with lib;

let
  opsLib = import ../../lib.nix;

  environment = concatStringsSep " "
    [ "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
in

{
  users.knownUsers = [ "builder" ];
  users.users.builder = {
    uid = 501;
    gid = 20;  # staff
    description = "Hydra";
    home = "/Users/builder";
    shell = "/bin/bash";
  };

  nix.trustedUsers = [ "root" "builder" ];

  # Create a ~/.bashrc containing source /etc/profile
  # (bash doesn't source the ones in /etc for non-interactive
  # shells and that breaks everything nix)
  system.activationScripts.postActivation.text = ''
    mkdir -p /Users/builder
    echo "source /etc/profile" > /Users/builder/.bashrc
    chown builder: /Users/builder/.bashrc
  '';

  environment.etc."per-user/builder/ssh/authorized_keys".text =
    concatMapStringsSep "\n" (key: ''
      command="${environment} ${config.nix.package}/bin/nix-store --serve --write" ${key}
    '') opsLib.buildSlaveKeys.macos + "\n";

}
