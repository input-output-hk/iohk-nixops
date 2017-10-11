{ localLib ? import ./lib.nix
, pkgs ? import (localLib.fetchNixPkgs) {}
}:

let
  extraDeps = with pkgs;
    [ wget awscli  # for scripts/aws.hs
      nodejs       # for cardano-sl/scripts/js/genesis-hash.js
                   #     ..which also needs `npm install blakejs canonical-json`
    ];
  drv = pkgs.haskell.lib.overrideCabal
         (import ./default.nix {}).iohk-ops
         (drv: { libraryHaskellDepends = extraDeps; });
in drv.env
