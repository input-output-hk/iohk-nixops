{ IOHKaccessKeyId, ... }:

{
  # this file will create an S3 bucket, and IAM role with access to that bucket
  # then give the report-server machine access to that role, and mount the bucket within the instance
  report-server = { pkgs, config, resources, ... }:
  let logsdir = config.services.report-server.logsdir;
  in {
    # nixops can only set this at creation, it will need to be manualy set
    deployment.ec2.instanceProfile = "report-server-logs-s3-wildcard";
    fileSystems.${logsdir} = {
      # mount unsets PATH when running this
      device = "/run/current-system/sw/bin/s3fs#${resources.s3Buckets.report-server-logs.name}";
      fsType = "fuse";
      options = [ "_netdev" "allow_other" "iam_role=auto" ];
    };
    environment.systemPackages = [ pkgs.s3fs ];
    # S3 is bad at appending to files, and it gets worse the larger
    # they are. So limit report-server's log to 20MB. NixOS runs this
    # daily at 5AM.
    services.logrotate.enable = true;
    services.logrotate.config = ''
      ${logsdir}/index.log {
        size 20M
        compress
        dateext
        rotate 10000
        su report-server report-server
      }
    '';
  };
  resources = {
    s3Buckets = {
      # if moved to another region, you must rename the bucket
      report-server-logs = { config, uuid, ... }: {
        region = "eu-central-1";
        accessKeyId = IOHKaccessKeyId;
      };
    };
  };
}
