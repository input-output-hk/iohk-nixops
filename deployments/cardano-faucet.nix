with (import ./../lib.nix);
{ globals, ... }:

{
  # faucet = import ./../modules/cardano-faucet.nix globals.fullMap.faucet;
  faucet = {
    imports = [
      ./common.nix
      ./amazon-base.nix
      ./network-wide.nix
      ./../modules/cardano-faucet.nix
      ./../modules/datadog.nix
    ];

    global.dnsHostname   = mkForce "faucet";

  };
}
