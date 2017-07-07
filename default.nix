{ pkgs ? (import <nixpkgs> {})
, compiler ? pkgs.haskell.packages.ghc802
}:

with pkgs.lib;
with (import <nixpkgs/pkgs/development/haskell-modules/lib.nix> { inherit pkgs;});

let
  prodMode = addConfigureFlags [ "-f-asserts" "-f-dev-mode" "--ghc-options=-DCONFIG=testnet"];
  addConfigureFlags = flags: drv: overrideCabal drv (drv: {
    configureFlags = flags;
  });

  socket-io-src = pkgs.fetchgit (removeAttrs (importJSON ./pkgs/engine-io.json) ["date"]);
  iohkpkgs = ((import pkgs/default.nix { inherit pkgs compiler; }).override {
  overrides = self: super: {
    cardano-sl-core = prodMode super.cardano-sl-core;
    cardano-sl = overrideCabal super.cardano-sl (drv: {
      doHaddock = false;
      patchPhase = ''
       export CSL_SYSTEM_TAG=linux64
      '';
      # production full nodes shouldn't use wallet as it means different constants
      configureFlags = [
        "-f-asserts"
        "-f-dev-mode"
        "-fwith-explorer"
        # https://github.com/NixOS/nixpkgs/pull/24692#issuecomment-306509337
        "--ghc-option=-optl-lm"
      ];
    });
    cardano-sl-static = justStaticExecutables self.cardano-sl;
    cardano-report-server-static = justStaticExecutables self.cardano-report-server;

    # TODO: https://github.com/input-output-hk/stack2nix/issues/7
    ether = addConfigureFlags ["-fdisable-tup-instances"] super.ether;

    # Gold linker fixes
    cryptonite = addConfigureFlags ["--ghc-option=-optl-pthread"] super.cryptonite;


    # sl-explorer
    # TODO: https://issues.serokell.io/issue/CSM-195
    snap = doJailbreak super.snap;
    # TODO: https://github.com/input-output-hk/stack2nix/issues/10
    socket-io = super.callCabal2nix "socket-io" "${socket-io-src}/socket-io" {};
    engine-io = super.callCabal2nix "engine-io" "${socket-io-src}/engine-io" {};
    engine-io-wai = super.callCabal2nix "engine-io-wai" "${socket-io-src}/engine-io-wai" {};

    cardano-sl-explorer = prodMode (super.callPackage ./pkgs/cardano-sl-explorer.nix { });
    cardano-sl-explorer-static = justStaticExecutables self.cardano-sl-explorer;

    #mkDerivation = args: super.mkDerivation (args // {
    #enableLibraryProfiling = false;
    #});
  };
});
  cabal2nixpkgs = rec {
    # extra packages to expose, that have no relation to pkgs/default.nix
    stack2nix = compiler.callPackage ./pkgs/stack2nix.nix {};
    iohk-ops =  compiler.callCabal2nix "iohk-ops" ./iohk {};
  };
in iohkpkgs // cabal2nixpkgs
