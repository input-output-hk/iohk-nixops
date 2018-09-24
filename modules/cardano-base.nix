with import ../lib.nix;

{ pkgs, nodes, config, resources, options, ...}:

{
    imports = [
      ./common.nix
      ./amazon-base.nix
      ./network-wide.nix
      ./dd-process-monitor.nix
    ];

    global.organisation = config.params.org;

    services.dnsmasq.enable = true;
    services.dnsmasq.servers = [ "127.0.0.1" ];

    # TODO: DEVOPS-8
    #deployment.ec2.ami = (import ./amis.nix).${config.deployment.ec2.region};
    deployment.ec2.region         = mkForce config.params.region;
    deployment.ec2.zone           = mkForce config.params.zone;
    deployment.ec2.accessKeyId    = config.params.accessKeyId;
    deployment.ec2.keyPair        = resources.ec2KeyPairs.${config.params.keyPairName};
    deployment.ec2.securityGroups =
      with config.params;
      let sgNames =
           optionals typeIsExplorer              [ "allow-to-explorer-${config.params.region}" ]
        ++ optionals typeIsFaucet                [ "allow-to-faucet-${config.params.region}" ]
        ++ optionals typeIsCore                  [ "allow-cardano-static-peers-${config.params.name}-${config.params.region}-${config.params.org}" ]
        ++ optionals typeIsRelay                 [ "allow-kademlia-public-udp-${config.params.region}"
                                                   "allow-cardano-public-tcp-${config.params.region}" ]
        ++ optionals config.global.enableEkgWeb  [ "allow-ekg-public-tcp-${config.params.region}-${config.params.org}" ];
      in map (resolveSGName resources)
             (if config.global.omitDetailedSecurityGroups
              then [ "allow-all-${config.params.region}-${config.params.org}" ]
              else sgNames);

    services.dd-agent.processMonitor =
      if config.params.typeIsExplorer then "cardano-explorer"
      else if config.params.typeIsFaucet then "cardano-faucet"
      else "cardano-node-simple";
  }
