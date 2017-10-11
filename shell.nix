{ localLib ? import ./lib.nix
, pkgs ? import (localLib.fetchNixPkgs) {}
, io-dev-mode ? false
}:

let
  extraDeps = with pkgs;
    [ wget awscli  # for scripts/aws.hs
      nodejs       # for cardano-sl/scripts/js/genesis-hash.js
                   #     ..which also needs `npm install blakejs canonical-json`
    ];
  iohk-ops = pkgs.haskell.lib.overrideCabal
             (import ./default.nix {}).iohk-ops
             (drv: { libraryHaskellDepends = extraDeps; });
  ioAlias = if io-dev-mode
            then ''runhaskell -iiohk iohk/iohk-ops.hs''
            else ''${iohk-ops}/bin/iohk-ops'';
in pkgs.lib.overrideDerivation iohk-ops.env
   (old: {
     shellHook = ''
       alias io='${ioAlias}'
     '';
    })
