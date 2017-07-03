{ ... }:

with (import ./../lib.nix);
{
  sl-explorer = { pkgs, config, ...}: {
    deployment.route53.accessKeyId = config.deployment.ec2.accessKeyId;
    deployment.route53.hostName = "cardano-explorer.aws.iohkdev.io";

    services.cardano-node.initialPeers = mkForce (peersFromFile (pkgs.fetchurl {
       url = "https://raw.githubusercontent.com/input-output-hk/daedalus/cardano-sl-0.4/installers/data/ip-dht-mappings";
       sha256 = "02nlxx28r1fc3ncc1qmzvxv6vlmy1i8rll10alr6fh9qf9nxwzbv";
     }));
  };
}
