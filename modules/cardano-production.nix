with import ../lib.nix;

params:
{ name, config, pkgs, resources, ... }: {
  imports = [
    ./production.nix
    ./datadog.nix
    ./papertrail.nix
  ];

  global.dnsHostname = if params.typeIsRelay then "cardano-node-${toString params.relayIndex}" else null;

  # Initial block is big enough to hold 3 months of transactions
  deployment.ec2.ebsInitialRootDiskSize = mkForce 700;

  deployment.ec2.instanceType =
    mkForce (if params.typeIsRelay && params.public == true
             then "m4.large"
             else "t2.large");
}
