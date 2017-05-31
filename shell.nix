{ ghcVer   ? "ghc802"
, intero   ? false
}: let

nixpkgs       = (import <nixpkgs> {}).fetchFromGitHub (builtins.fromJSON (builtins.readFile ./nixpkgs-src.json));
pkgs          = import nixpkgs {};
compiler      = pkgs.haskell.packages."${ghcVer}";

ghcOrig       = import ./default.nix { inherit pkgs compiler; };

githubSrc     =      repo: rev: sha256:       pkgs.fetchgit  { url = "https://github.com/" + repo; rev = rev; sha256 = sha256; };
overC         =                               pkgs.haskell.lib.overrideCabal;
overCabal     = old:                    args: overC old (oldAttrs: (oldAttrs // args));
overGithub    = old: repo: rev: sha256: args: overC old ({ src = githubSrc repo rev sha256; }     // args);
overHackage   = old: version:   sha256: args: overC old ({ version = version; sha256 = sha256; } // args);

ghc       = ghcOrig.override (oldArgs: {
  overrides = with pkgs.haskell.lib; new: old:
  let parent = (oldArgs.overrides or (_: _: {})) new old;
  in with new; parent // {
      intero         = overGithub  old.intero "commercialhaskell/intero"
                       "e546ea086d72b5bf8556727e2983930621c3cb3c" "1qv7l5ri3nysrpmnzfssw8wvdvz0f6bmymnz1agr66fplazid4pn" { doCheck = false; };
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
  shellHook =
  ''
    export NIX_PATH=nixpkgs=${nixpkgs}
    echo   NIX_PATH set to $NIX_PATH
  '';
  license      = stdenv.lib.licenses.mit;
};

drv = (pkgs.haskell.lib.addBuildTools
(ghc.callPackage drvf { })
(if intero
 then [ pkgs.cabal-install
        pkgs.stack
        ghc.intero ]
 else []));

in drv.env
