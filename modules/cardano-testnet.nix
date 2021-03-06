with (import ./../lib.nix);

params:
{
  imports = [
    ./testnet.nix
    ./monitoring-exporters.nix
  ];

  services.monitoring-exporters.papertrail.enable = true;

  global.dnsHostname = if params.typeIsRelay then "cardano-node-${toString params.relayIndex}" else null;
}
