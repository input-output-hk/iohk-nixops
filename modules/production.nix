{ name, config, resources, ... }:

with import ../lib.nix;
{
  config = {

    global = {
      allocateElasticIP = true;
      enableEkgWeb      = false;
      dnsDomainname     = "cardano-mainnet.iohk.io";
    };

    services = {
      # temporary space until https://github.com/NixOS/nixpkgs/pull/30141 is in effect
      dd-agent.tags              = ["env:production" "depl:${config.deployment.name}"];

      # DEVOPS-64: disable log bursting
      journald.rateLimitBurst    = 0;
    };

  };
}
