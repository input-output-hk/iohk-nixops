let
  localLib = import ./lib.nix;
in
{ system ? builtins.currentSystem
, config ? {}
, pkgs ? (import (localLib.fetchNixPkgs) { inherit system config; })
, compiler ? pkgs.haskell.packages.ghc802
, enableDebugging ? false
, enableProfiling ? false
}:

with pkgs.lib;
with pkgs.haskell.lib;

let
  nixops =
    let
      # nixopsUnstable = /path/to/local/src
      nixopsUnstable = pkgs.fetchFromGitHub {
        owner = "NixOS";
        repo = "nixops";
        rev = "92034401b5291070a93ede030e718bb82b5e6da4";
        sha256 = "139mmf8ag392w5mn419k7ajp3pgcz6q349n7vm7gsp3g4sck2jjn";
      };
    in (import "${nixopsUnstable}/release.nix" {
         nixpkgs = localLib.fetchNixPkgs;
        }).build.${system};
  iohk-ops-extra-runtime-deps = [
    pkgs.gitFull pkgs.nix-prefetch-scripts compiler.yaml
    pkgs.wget
    pkgs.file
    cardano-sl-pkgs.cardano-sl-auxx
    cardano-sl-pkgs.cardano-sl-tools
    nixops
    pkgs.terraform_0_11
  ];
  # we allow on purpose for cardano-sl to have it's own nixpkgs to avoid rebuilds
  cardano-sl-src = builtins.fromJSON (builtins.readFile ./cardano-sl-src.json);
  cardano-sl-pkgs = import (pkgs.fetchgit cardano-sl-src) {
    gitrev = cardano-sl-src.rev;
    inherit enableDebugging enableProfiling;
  };
in {
  inherit nixops;

  iohk-ops = pkgs.haskell.lib.overrideCabal
             (compiler.callPackage ./iohk/default.nix {})
             (drv: {
                executableToolDepends = [ pkgs.makeWrapper ];
                libraryHaskellDepends = iohk-ops-extra-runtime-deps;
                postInstall = ''
                  wrapProgram $out/bin/iohk-ops \
                  --prefix PATH : "${pkgs.lib.makeBinPath iohk-ops-extra-runtime-deps}"
                '';
             });
} // cardano-sl-pkgs
