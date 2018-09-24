{ pkgs ? import (builtins.fetchTarball https://nixos.org/channels/nixpkgs-18.03-darwin/nixexprs.tar.xz) {} }:

let
  ghc = pkgs.haskellPackages.ghcWithPackages (ps: [ ps.turtle ]);
in
  pkgs.stdenv.mkDerivation {
    name = "deploy-nix-darwin";
    buildInputs = [ ghc pkgs.nixStable ];
    shellHook = "eval $(egrep ^export ${ghc}/bin/ghc)";
    src = ./.;
    buildCommand = ''
      mkdir -p $out/bin
      cp -R "$src/"* $out
      ghc -o $out/bin/deploy $out/deploy.hs
      ghc -o $out/bin/prepare $out/prepare.hs
    '';
  }
