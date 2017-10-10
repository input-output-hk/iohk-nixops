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
  cardano-sl-src = builtins.fromJSON (builtins.readFile ./../cardano-sl-src.json);
  cardanoSrc = pkgs.fetchgit cardano-sl-src;
in rec {
  inherit (jobs) iohk-ops nixops;
  tests          = import ./../tests     { inherit pkgs; supportedSystems = [ "x86_64-linux" ]; };
} // (import "${cardanoSrc}/release.nix" { cardano = { outPath = cardanoSrc; rev = cardano-sl-src.rev; }; })
