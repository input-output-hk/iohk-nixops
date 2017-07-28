let
  localLib = import ./lib.nix;
  nixpkgs  = localLib.fetchNixPkgs;
  pkgs     = import nixpkgs {};
  iohkpkgs = import ./default.nix {};
in

{ ... }:
let
  default = import ./iohk/default.nix; # iohkpkgs.iohk-ops;
  drv     = iohkpkgs.callPackage default {};
  drv'    = pkgs.haskell.lib.overrideCabal
            drv
            (old: {
              libraryHaskellDepends =
                 [ pkgs.cabal-install pkgs.stack iohkpkgs.intero ];
             });
  drv''   = pkgs.lib.overrideDerivation
            drv'.env
            (old: {
              shellHook = ''
                export NIX_PATH=nixpkgs=${nixpkgs}
                export NIX_PATH_LOCKED=1
                echo   NIX_PATH set to $NIX_PATH >&2
            
                alias git-rev='git log -n1 --pretty=oneline'
                echo "Aliases:"                                                                                                        >&2
                echo                                                                                                                   >&2
                echo "  git-rev:              git log -n1 --pretty=oneline"                                                            >&2
                echo                                                                                                                   >&2
              '';
             });
in
  drv''
