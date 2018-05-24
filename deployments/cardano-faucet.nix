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
      source-wallet-config = builtins.toString ../../cardano-sl/faucet/wallet-source.json;
      logging-config = builtins.toString ../../cardano-sl/faucet/logging.cfg;
      public-certificate = builtins.toString ../../cardano-sl/faucet/tls/ca.crt;
      private-key = builtins.toString ../../cardano-sl/faucet/tls/server.key;
    };

  };
}
