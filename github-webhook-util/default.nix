{ haskellPackages, runCommand, binutils-unwrapped, haskell }:

let
  hpkgs = haskellPackages.override {
    overrides = self: super: {
      influxdb = haskell.lib.dontCheck (self.callHackage "influxdb" "1.6.0.2" {});
    };
  };
  ghc = hpkgs.ghcWithPackages (p: with p; [
    aeson
    github
    influxdb
    time
    operational
    servant-github-webhook
    encode-string
  ]);
in runCommand "github-webhook-util" { buildInputs = [ ghc hpkgs.ghcid ]; } ''
  cp -v ${./Main.hs} ./Main.hs
  mkdir -pv $out/bin
  chmod -R +w .
  ghc Main.hs -o $out/bin/github-webhook-util
  ln -s github-webhook-util $out/bin/import-prs
  ${binutils-unwrapped}/bin/strip $out/bin/github-webhook-util
  patchelf --shrink-rpath $out/bin/github-webhook-util
''
