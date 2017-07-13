with (import ./../lib.nix);

{ config, pkgs, resources, ... }: {
  imports = [
    ./datadog.nix
    ./papertrail.nix
    ./common.nix
  ];

  # DEVOPS-64: disable log bursting
  services.journald.rateLimitBurst = 0;

  services.cardano-node = {
    saveCoreDumps = true;
  };

  deployment.ec2.elasticIPv4 = resources.elasticIPs.${"nodeip" + toString config.services.cardano-node.testIndex};

  deployment.route53.accessKeyId = config.deployment.ec2.accessKeyId;
  deployment.route53.hostName = "cardano-node-${toString config.services.cardano-node.testIndex}.aws.iohkdev.io";

  services.cardano-node.systemStart = mkForce 1499433433;

  services.dd-agent.tags = ["env:staging"];
  services.dd-agent.processConfig = ''
    init_config:

    instances:
    - name: cardano-node
      search_string: ['cardano-node']
      exact_match: False
      thresholds:
        critical: [1, 1]
  '';
}
