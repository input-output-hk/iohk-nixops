let
  localLib = import ./lib.nix;
in
{ system ? builtins.currentSystem
, config ? {}
, pkgs ? (import (localLib.fetchNixPkgs) { inherit system config; })
, compiler ? pkgs.haskellPackages
, enableDebugging ? false
, enableProfiling ? false
, cardanoRevOverride ? null
}:

with pkgs.lib;
with pkgs.haskell.lib;

let
  nixops =
    let
      # nixopsUnstable = /path/to/local/src
      nixopsUnstable = pkgs.fetchFromGitHub {
        owner = "rvl";
        repo = "nixops";
        rev = "ab86e522373f133e2412bd28a864989eb48f58ec";
        sha256 = "0xfwyh21x6r2x7rjgf951gkkld3h10x05qr79im3gvhsgnq3nzmv";
      };
    in (import "${nixopsUnstable}/release.nix" {
         nixpkgs = localLib.fetchNixPkgs;
        }).build.${system};
  iohk-ops-extra-runtime-deps = with pkgs; [
    gitFull nix-prefetch-scripts compiler.yaml
    wget
    file
    nixops
    coreutils
    gnupg
  ];
  # we allow on purpose for cardano-sl to have it's own nixpkgs to avoid rebuilds
  cardano-sl-src = let
    try = builtins.tryEval <cardano-sl>;
    cfg = builtins.fromJSON (builtins.readFile ./cardano-sl-src.json);
    fixedSrc = pkgs.fetchgit cfg;
  in if try.success then
    builtins.trace "using search host <cardano-sl>" try.value
  else fixedSrc;
  cardano-sl-src-phase2 = let
    localOverride = {
      outPath = builtins.fetchTarball "https://github.com/input-output-hk/cardano-sl/archive/${cardanoRevOverride}.tar.gz";
      rev = cardanoRevOverride;
    };
  in if (cardanoRevOverride != null) then localOverride else cardano-sl-src;
  cardano-sl-pkgs = import cardano-sl-src-phase2 ({
    inherit enableDebugging enableProfiling;
  } // optionalAttrs (cardano-sl-src-phase2 ? rev) {
    gitrev = cardano-sl-src-phase2.rev;
  });
  github-webhook-util = pkgs.callPackage ./github-webhook-util { };

  iohk-ops = pkgs.haskell.lib.overrideCabal
             (compiler.callPackage ./iohk/default.nix {})
             (drv: {
                executableToolDepends = [ pkgs.makeWrapper ];
                libraryHaskellDepends = iohk-ops-extra-runtime-deps;
                postInstall = ''
                  cp -vs $out/bin/iohk-ops $out/bin/io
                  wrapProgram $out/bin/iohk-ops \
                  --prefix PATH : "${pkgs.lib.makeBinPath iohk-ops-extra-runtime-deps}"
                '';
             });

  iohk-ops-integration-test = let
    parts = with cardano-sl-pkgs; [ cardano-sl-auxx cardano-sl-tools iohk-ops ];
  in pkgs.runCommand "iohk-ops-integration-test" {} ''
    mkdir -p $out/nix-support
    export PATH=${pkgs.lib.makeBinPath parts}:$PATH
    export CARDANO_SL_CONFIG=${cardano-sl-pkgs.cardano-sl-config}
    mkdir test
    cp ${iohk-ops.src}/test/Spec.hs test  # a file to hash
    iohk-ops-integration-test | tee $out/test.log
    if [ $? -ne 0 ]; then
      touch $out/nix-support/failed
    fi
    exit 0
  '';

in {
  inherit nixops iohk-ops iohk-ops-integration-test github-webhook-util;
  terraform = pkgs.callPackage ./terraform/terraform.nix {};
  mfa = pkgs.callPackage ./terraform/mfa.nix {};

} // cardano-sl-pkgs
