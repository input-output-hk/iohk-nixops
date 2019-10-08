let
  localLib = import ./lib.nix;
in
{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
, pkgs ? (import (localLib.nixpkgs) { inherit system crossSystem config; })
, compiler ? pkgs.haskellPackages
, cardanoRevOverride ? null
, cardanoNodeRevOverride ? null
, ...
}@args:

with pkgs.lib;
with pkgs.haskell.lib;

let
  sources = localLib.sources;
  # nixopsUnstable = /path/to/local/src
      nixopsUnstable = sources.nixops-iohk;
  log-classifier-web = (import log-classifier-src {}).haskellPackages.log-classifier-web;
  nixops =
    let
    in (import "${nixopsUnstable}/release.nix" {
         inherit (localLib) nixpkgs;
         p = (p: [ p.aws p.packet ] );
        }).build.${system};
  log-classifier-src = pkgs.fetchFromGitHub {
    owner = "input-output-hk";
    repo = "log-classifier";
    rev = "fff61ebb4d6380796ec7a6438a873e6826236f2b";
    sha256 = "1sc56xpbljm63dh877cy4agqjvv5wqc1cp9y5pdwzskwf7h4302g";
  };
  iohk-ops-extra-runtime-deps = with pkgs; [
    gitFull nix-prefetch-scripts compiler.yaml
    wget
    file
    nixops
    coreutils
    gnupg
  ];

  cardano-sl-src = sources.cardano-sl.revOverride cardanoRevOverride;
  cardano-sl-pkgs = import cardano-sl-src {
    gitrev = cardano-sl-src.rev;
  };
  mantis-pkgs     = localLib.fetchProjectPackages "mantis"     <mantis>     ./goguen/pins   mantisRevOverride  args;
  cardano-node-pkgs = import (sources.cardano-node.revOverride cardanoNodeRevOverride) {};

  github-webhook-util = pkgs.callPackage ./github-webhook-util { };

  iohk-ops = pkgs.haskell.lib.overrideCabal
             (compiler.callPackage ./iohk/default.nix {})
             (drv: {
                executableToolDepends = [ pkgs.makeWrapper ];
                libraryHaskellDepends = (drv.libraryHaskellDepends or []) ++ iohk-ops-extra-runtime-deps;
                postInstall = ''
                  cp -vs $out/bin/iohk-ops $out/bin/io
                  wrapProgram $out/bin/iohk-ops \
                  --prefix PATH : "${pkgs.lib.makeBinPath iohk-ops-extra-runtime-deps}"
                '';
             });

  iohk-ops-integration-test = let
    parts = with cardano-sl-pkgs.nix-tools.exes; [ cardano-sl-auxx cardano-sl-tools iohk-ops ];
  in pkgs.runCommand "iohk-ops-integration-test" {} ''
    mkdir -p $out/nix-support
    export PATH=${pkgs.lib.makeBinPath parts}:$PATH
    export CARDANO_SL_CONFIG=${cardano-sl-pkgs.cardanoConfig}
    mkdir test
    cp ${iohk-ops.src}/test/Spec.hs test  # a file to hash
    iohk-ops-integration-test | tee $out/test.log
    if [ $? -ne 0 ]; then
      touch $out/nix-support/failed
    fi
    exit 0
  '';
  defaultIohkNix = sources.iohk-nix;

  cachecacheSrc = sources.cachecache;
  IFDPins = pkgs.writeText "ifd-pins" ''
    nixops: ${nixopsUnstable}
    nixpkgs: ${pkgs.path}
    iohk-nix: ${defaultIohkNix}
  '';
  cachecache = pkgs.callPackage cachecacheSrc {};
in {
  inherit nixops iohk-ops iohk-ops-integration-test github-webhook-util IFDPins log-classifier-web cachecache cardano-node-pkgs;
  terraform = pkgs.callPackage ./terraform/terraform.nix {};
  mfa = pkgs.callPackage ./terraform/mfa.nix {};

  checks = let
    src = localLib.cleanSourceTree ./.;
  in {
    shellcheck = pkgs.callPackage ./scripts/shellcheck.nix { inherit src; };
  };
} // cardano-sl-pkgs
