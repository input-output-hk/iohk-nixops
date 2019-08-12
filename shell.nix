{ localLib ? import ./lib.nix
, pkgs ? localLib.pkgs
}:

let
  iohkpkgs = import ./default.nix {};
  iohk-ops = iohkpkgs.iohk-ops;
  justIo = pkgs.mkShell {
    name = "io";
    buildInputs = with pkgs; [ iohk-ops terraform_0_11 iohkpkgs.nixops ];
    passthru = {
      inherit ioSelfBuild withAuxx;
    };
    shellHook = ioShellHook;
  };
  ioSelfBuild = pkgs.lib.overrideDerivation iohk-ops.env (drv: {
    shellHook = ''
      function io {
        cabal exec iohk-ops -- "$@"
      }
      function ghcid-io {
        ${pkgs.haskellPackages.ghcid}/bin/ghcid -c "ghci -iiohk -iiohk/common iohk/iohk-ops.hs"
      }
    '';
  });
  withAuxx = pkgs.mkShell {
    name = "io-with-auxx";
    buildInputs = [
      iohk-ops
      iohkpkgs.nix-tools.exes.cardano-sl-auxx
      iohkpkgs.nix-tools.exes.cardano-sl-tools
      # todo, switch run nix-shell to nix run
      pkgs.bashInteractive
    ];
    shellHook = ''
      ${ioShellHook}
      for prog in cardano-keygen cardano-x509-certificates cardano-auxx; do
        source <($prog --bash-completion-script `type -p $prog`)
      done
    '';
  };
  ioShellHook = ''
    source <(iohk-ops --bash-completion-script `type -p iohk-ops`)
    complete -o filenames -F _iohk-ops io
  '';
in justIo
