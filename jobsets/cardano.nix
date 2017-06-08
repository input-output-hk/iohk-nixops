{ pkgs ? (import <nixpkgs> {})}:

with pkgs;

let
  iohkpkgs = import ./../default.nix {};
in rec {
  inherit (iohkpkgs) cardano-report-server-static cardano-sl-static cardano-sl-explorer-static;
  stack2nix = iohkpkgs.callPackage ./../pkgs/stack2nix.nix {};
}
