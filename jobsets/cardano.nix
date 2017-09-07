let
  fixedNixpkgs = (import ../lib.nix).fetchNixPkgs;
in { pkgs ? (import fixedNixpkgs {})
   , supportedSystems ? [ "x86_64-linux" "x86_64-darwin" ]
   , scrubJobs ? true
   }:

with import (fixedNixpkgs + "/pkgs/top-level/release-lib.nix") { inherit supportedSystems scrubJobs; packageSet = import ../.; };

let
  iohkpkgs = import ./../default.nix { inherit pkgs; };
  jobs = mapTestOn (packagePlatforms iohkpkgs);
  cardanoSrc = pkgs.fetchgit (builtins.fromJSON (builtins.readFile ./../cardano-sl-src.json));
in rec {
  inherit (jobs) iohk-ops;
  tests          = import ./../tests     { inherit pkgs; supportedSystems = [ "x86_64-linux" ]; };
} // (import "${cardanoSrc}/release.nix" {})
