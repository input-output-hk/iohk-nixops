{ accessKeyId, ... }:

with (import ./../lib.nix);
{
  report-server = { resources, ...}: {
    imports = [
      ./../modules/datadog.nix
      ./../modules/papertrail.nix
    ];

    services.dd-agent.tags = ["env:staging"];

    deployment.ec2.elasticIPv4 = resources.elasticIPs.report-server-ip;

    deployment.route53.accessKeyId = accessKeyId;
    deployment.route53.hostName = "report-server.aws.iohkdev.io";
  };
  resources = {
    elasticIPs = {
      report-server-ip = { inherit region accessKeyId; };
    };
  };
}
