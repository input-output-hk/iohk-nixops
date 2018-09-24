{ lib, ... }:

with lib;

let
  localLib = import ../lib.nix;
in
{
  imports = [ ./auto-gc.nix ./nix_nsswitch.nix ];
  services = {
    dd-agent.tags = ["group:hydra-and-slaves"];
  };

  nix = {
    binaryCaches = mkForce [ "https://cache.nixos.org" ];
    extraOptions = ''
      # max of 2 hours for any given derivation on linux
      # note darwin is slower, and should have a higher timeout, maybe 4h?
      timeout = ${toString (3600 * 2)}
    '';
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = map (key: ''
    command="nice -n20 nix-store --serve --write" ${key}
  '') localLib.buildSlaveKeys.linux;
}
