{ localLib ? import ./lib.nix
, pkgs ? import (localLib.fetchNixPkgs) {}
}:

let
  iohkpkgs = import ./default.nix {};
  iohk-ops = iohkpkgs.iohk-ops;
  justIo = pkgs.runCommand "shell" {
    buildInputs = with pkgs; [ iohk-ops terraform_0_11 iohkpkgs.nixops cabal-install ];
    passthru = {
      inherit ioSelfBuild withAuxx;
    };
  } "echo use nix-shell";
  ioSelfBuild = pkgs.lib.overrideDerivation iohk-ops.env (drv: {
    shellHook = ''
      function io {
        runhaskell -iiohk iohk/iohk-ops.hs "$@"
      }
      function ghcid-io {
        ${pkgs.haskellPackages.ghcid}/bin/ghcid -c "ghci -iiohk iohk/iohk-ops.hs"
      }
    '';
  });
  withAuxx = pkgs.runCommand "shell" {
    buildInputs = [
      iohk-ops
      iohkpkgs.cardano-sl-auxx
      iohkpkgs.cardano-sl-tools
    ];
  } "echo use nix-shell";
in justIo
