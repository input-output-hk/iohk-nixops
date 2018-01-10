{ name, config, resources, ... }:

with import ./../lib.nix;
{
  config = {

    global = {
      allocateElasticIP            = false;
      enableEkgWeb                 = true;
      dnsHostname                  = "${name}-${config.deployment.name}";
      dnsDomainname                = "aws.iohkdev.io";
      omitDetailedSecurityGroups   = true;
    };

    services = {
      # DEVOPS-64: disable log bursting
      journald.rateLimitBurst    = 0;
    };

  };
}
