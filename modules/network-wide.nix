{ name, config, resources, ... }:

with import ./../lib.nix;
{
  imports = [ ./globals.nix ];
  config.deployment = {
    ec2 = {
      elasticIPv4 = if config.global.allocateElasticIP
                    then resources.elasticIPs.${name + "-ip"} else "";
      securityGroups = map (resolveSGName resources)
        (optionals (! config.global.omitDetailedSecurityGroups) [
          "allow-deployer-ssh-${config.deployment.ec2.region}-${config.global.organisation}"
        ]);
    };

    route53 = optionalAttrs (config.global.dnsHostname   != null &&
                             config.global.dnsDomainname != null) {
      accessKeyId = config.deployment.ec2.accessKeyId;
      hostName    = config.global.dnsHostname +"."+ config.global.dnsDomainname;
    };
  };
  options = {
  };
}
