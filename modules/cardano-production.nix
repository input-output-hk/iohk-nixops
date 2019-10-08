with import ../lib.nix;

params:
{ name, config, pkgs, lib, resources, ... }: {
  imports = [
    ./production.nix
    ./monitoring-exporters.nix
  ];

  services.monitoring-exporters.papertrail.enable = true;

  global.dnsHostname = if params.typeIsRelay then "cardano-node-${toString params.relayIndex}" else null;

  # Initial block is big enough to hold 3 months of transactions
  deployment.ec2.ebsInitialRootDiskSize = mkForce 700;

  deployment.ec2.instanceType =
    mkForce (if params.typeIsRelay && params.public == true
             then "m4.large"
             else if (params.nodeImpl == "haskell")
             then "t3.xlarge"
             else "t2.large");

  boot.loader.grub = lib.mkIf (config.deployment.ec2.instanceType == "t3.xlarge") {
    device = lib.mkForce "/dev/nvme0n1"; # t3.xlarge has an nvme disk, and amazon-image.nix isnt handling it right yet
  };
}
