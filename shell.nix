{ pkgs     ? import ((import <nixpkgs> {}).fetchFromGitHub (builtins.fromJSON (builtins.readFile ./nixpkgs-src.json))) {}
, compiler ? pkgs.haskell.packages.ghc802
, intero   ? false
}:

let

ghcOrig   = import ./default.nix { inherit pkgs compiler; };
overcabal = pkgs.haskell.lib.overrideCabal;
hubsrc    =      repo: rev: sha256:       pkgs.fetchgit { url = "https://github.com/" + repo; rev = rev; sha256 = sha256; };
overc     = old:                    args: overcabal old (oldAttrs: (oldAttrs // args));
overhub   = old: repo: rev: sha256: args: overc old ({ src = hubsrc repo rev sha256; }       // args);
overhage  = old: version:   sha256: args: overc old ({ version = version; sha256 = sha256; } // args);
ghc       = ghcOrig.override (oldArgs: {
  overrides = with pkgs.haskell.lib; new: old:
  let parent = (oldArgs.overrides or (_: _: {})) new old;
  in with new; parent // {
      intero         = overhub  old.intero "commercialhaskell/intero" "e546ea086d72b5bf8556727e2983930621c3cb3c" "1qv7l5ri3nysrpmnzfssw8wvdvz0f6bmymnz1agr66fplazid4pn" { doCheck = false; };
    };
  });

###
###
###
drvf =
{ mkDerivation, stdenv, src ? ./.
, base, turtle, cassava, vector, safe, aeson, yaml, lens-aeson
}:
mkDerivation {
  pname = "iohk-nixops";
  version = "0.0.1";
  src = src;
  isLibrary = false;
  isExecutable = true;
  doHaddock = false;
  executableHaskellDepends = [
   base turtle cassava vector safe aeson yaml lens-aeson
  ];
  # description  = "Visual mind assistant";
  license      = stdenv.lib.licenses.agpl3;
};

drv = (pkgs.haskell.lib.addBuildTools
(ghc.callPackage drvf { })
(if intero
 then [ pkgs.cabal-install
        pkgs.stack
        ghc.intero ]
 else []));

in drv.env
