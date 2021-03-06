{ lib, ... }:

with lib;

let
  commonLib = import ../lib.nix;
in
{
  imports = [ ./auto-gc.nix
              ./nix_nsswitch.nix
            ];

  nix = {
    binaryCaches = mkForce [ "https://cache.nixos.org" ];
    extraOptions = ''
      # Max of 2 hours to build any given derivation on Linux.
      # See ../nix-darwin/modules/basics.nix for macOS.
      timeout = ${toString (3600 * 2)}
    '';
  };

  users.extraUsers.root.openssh.authorizedKeys.keys =
    commonLib.ciInfraKeys ++
    map (key: ''
      command="nice -n20 nix-store --serve --write" ${key}
    '') commonLib.buildSlaveKeys.linux;
}
