{ ... }:

{
  faucet = {
    imports = [
      ./common.nix
      ./amazon-base.nix
      ./network-wide.nix
      ./../modules/cardano-faucet.nix
      ./../modules/datadog.nix
    ];

    services.faucet.faucet-config = {
      source-wallet-config = builtins.toString ./../static/wallet-source.json;
    };

  };
}
