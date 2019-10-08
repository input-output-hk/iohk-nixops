{ role ? "hydra-slave", host, port }:

let
  pkgs = import (import ../fetch-nixpkgs.nix) {};
  nix-darwin = pkgs.fetchFromGitHub {
    owner = "LnL7";
    repo = "nix-darwin";
    rev = "8d557721a9511d8e6b26c140363ab44d2c98f76b";
    sha256 = "0gv4b3yfi4k01gyy6djjmln44q7hg3iqm4lalm9b7kgzmgnpx4fp";
  };
  system = (import nix-darwin {
    nixpkgs = pkgs.path;
    configuration = "${guestConfDir}/darwin-configuration.nix";
    system = "x86_64-darwin";
  }).system;
  lib = pkgs.lib;

  # this ensures that nix-darwin can find everything it needs, but wont see things it doesnt need
  # that prevents the guest from being rebooted when things it doesnt read get modified
  guestConfDir = pkgs.runCommand "guest-config-dir" {
    inherit host port;
  } ''
    mkdir -pv $out
    cd $out
    mkdir -pv iohk-ops/nix-darwin
    cd iohk-ops
    cp -r --no-preserve=mode ${./roles} nix-darwin/roles
    cp -r --no-preserve=mode ${./modules} nix-darwin/modules
    cp -r --no-preserve=mode ${./services} nix-darwin/services
    cp ${./test.nix} nix-darwin/test.nix
    cp ${../lib.nix} lib.nix
    mkdir nix
    cp ${../nix/sources.json} ./nix/
    cp ${../nix/sources.nix} ./nix/
    mkdir lib
    cp ${../lib/ssh-keys.nix} lib/ssh-keys.nix
    cp ${../fetch-nixpkgs.nix} fetch-nixpkgs.nix
    cd ..
    cp -r ${../modules/macs/guest}/* .
    substituteAll apply.sh apply.sh
    cd iohk-ops/nix-darwin/roles
    ln -sv ${role}.nix active-role.nix
  '';
in {
  inherit nix-darwin system guestConfDir;
}
