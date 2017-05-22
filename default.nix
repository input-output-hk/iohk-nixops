{ pkgs ? (import <nixpkgs> {})
, compiler ? pkgs.haskell.packages.ghc802
, builder-threads ? 8
}:

with (import <nixpkgs/pkgs/development/haskell-modules/lib.nix> { inherit pkgs;});

let
  lib = import <nixpkgs/lib>;
  prodMode = drv: overrideCabal drv (drv: {
    configureFlags = [ "-f-asserts" "-f-dev-mode"];
  });
  socket-io-src = pkgs.fetchgit (removeAttrs (lib.importJSON ./pkgs/engine-io.json) ["date"]);
  cardano-sl-src = pkgs.fetchgit (removeAttrs (lib.importJSON ./pkgs/cardano-sl.json) ["date"]);

  builder-cores   = builtins.div builder-threads 2;
  buildSubset = subset: drv: overrideCabal drv (drv: {
    buildTarget = subset;
  });
  buildSpeedupFlagsMarlowScaling = drv : appendConfigureFlag drv
    "--ghc-option=-rtsopts --ghc-option=+RTS --ghc-option=-N${toString builder-threads} --ghc-option=-A128m --ghc-option=-n2m --ghc-option=-qb0 --ghc-option=-qn${toString builder-cores} --ghc-option=-RTS";
in compiler.override {
  overrides = self: super: {
    # To generate these go to ./pkgs and run ./generate.sh
    universum = super.callPackage ./pkgs/universum.nix { };
    serokell-util = super.callPackage ./pkgs/serokell-util.nix { };
    acid-state = super.callPackage ./pkgs/acid-state.nix { };
    log-warper = super.callPackage ./pkgs/log-warper.nix { };
    ed25519 = super.callPackage ./pkgs/ed25519.nix { };
    rocksdb = super.callPackage ./pkgs/rocksdb-haskell.nix { rocksdb = pkgs.rocksdb; };
    kademlia = super.callPackage ./pkgs/kademlia.nix { };
    node-sketch = super.callPackage ./pkgs/time-warp-nt.nix { };
    cardano-report-server = super.callPackage ./pkgs/cardano-report-server.nix { };
    cardano-crypto = super.callPackage ./pkgs/cardano-crypto.nix { };
    plutus-prototype = super.callPackage ./pkgs/plutus-prototype.nix { };
    network-transport = super.callPackage ./pkgs/network-transport.nix { };
    network-transport-tcp = super.callPackage ./pkgs/network-transport-tcp.nix { };

    # servant-multipart needs servant 0.10
    servant = dontCheck super.servant_0_10;
    servant-server = super.servant-server_0_10;
    servant-swagger = super.servant-swagger_1_1_2_1;
    servant-docs = super.servant-docs_0_10;

    memory = super.memory_0_14_5;
    cryptonite = super.cryptonite_0_23;
    foundation = super.foundation_0_0_8;

    # sl-explorer fixes
    map-syntax = dontCheck super.map-syntax;
    snap = dontCheck super.snap;

    socket-io = super.callCabal2nix "socket-io" "${socket-io-src}/socket-io" {};
    engine-io = super.callCabal2nix "engine-io" "${socket-io-src}/engine-io" {};
    engine-io-wai = super.callCabal2nix "engine-io-wai" "${socket-io-src}/engine-io-wai" {};

    # TODO: https://github.com/NixOS/cabal2nix/issues/261
    cardano-sl-core = prodMode (super.callCabal2nix "cardano-sl-core" "${cardano-sl-src}/core" {});
    cardano-sl-db = super.callCabal2nix "cardano-sl-db" "${cardano-sl-src}/db" {};
    cardano-sl-infra = prodMode (super.callCabal2nix "cardano-sl-infra" "${cardano-sl-src}/infra" {});
    cardano-sl-lrc = super.callCabal2nix "cardano-sl-lrc" "${cardano-sl-src}/lrc" {};
    cardano-sl-update = super.callCabal2nix "cardano-sl-update" "${cardano-sl-src}/update" {};
    cardano-sl-explorer = prodMode (super.callPackage ./pkgs/cardano-sl-explorer.nix { });

    cardano-sl = overrideCabal (super.callCabal2nix "cardano-sl" cardano-sl-src {}) (drv: {
      doHaddock = false;
      patchPhase = ''
       export CSL_SYSTEM_TAG=linux64
      '';
      # production full nodes shouldn't use wallet as it means different constants
      configureFlags = [ "-f-asserts" "-f-dev-mode" "-fwith-explorer"];
    });
    cardano-sl-static =
      buildSpeedupFlagsMarlowScaling
      (buildSubset ("cardano-node")
       (dontCheck (linkWithGold (justStaticExecutables self.cardano-sl))));
    cardano-report-server-static = justStaticExecutables self.cardano-report-server;
    cardano-sl-explorer-static = justStaticExecutables self.cardano-sl-explorer;

    #mkDerivation = args: super.mkDerivation (args // {
    #enableLibraryProfiling = false;
    #});
  };
}
