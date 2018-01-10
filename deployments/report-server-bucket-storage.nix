{ IOHKaccessKeyId, ... }:

{
  # this file will create an S3 bucket, and IAM role with access to that bucket
  # then give the report-server machine access to that role, and mount the bucket within the instance
  report-server = { pkgs, resources, ... }: {
    # nixops can only set this at creation, it will need to be manualy set
    deployment.ec2.instanceProfile = resources.iamRoles.report-role.name;
    fileSystems."/var/lib/report-server" = {
      # mount unsets PATH when running this
      device = "/run/current-system/sw/bin/s3fs#${resources.s3Buckets.report-server-logs.name}";
      fsType = "fuse";
      options = [ "_netdev" "allow_other" ("iam_role=${resources.iamRoles.report-role.name}") ];
    };
    environment.systemPackages = [ pkgs.s3fs ];
  };
  resources = {
    s3Buckets = {
      # if moved to another region, you must rename the bucket
      report-server-logs = { config, uuid, ... }: {
        region = "eu-central-1";
        accessKeyId = IOHKaccessKeyId;
      };
    };
    iamRoles = {
      report-role = { config, uuid, ...}: {
        accessKeyId = IOHKaccessKeyId;
        assumeRolePolicy = builtins.toJSON {
          Version = "2008-10-17";
          Statement = [
            {
              Action = "sts:AssumeRole";
              Effect = "Allow";
              Principal = {
                Service = "ec2.amazonaws.com";
                # allows main IOHK account to assume-role for testing
                AWS = "arn:aws:iam::741691143009:root";
              };
            }
          ];
        };
        policy = builtins.toJSON {
          Version = "2012-10-17";
          Statement = [
            {
              Effect = "Allow";
              Action = "s3:*";
              Resource = "arn:aws:s3:::charon-${uuid}-report-server-logs";
            }
            {
              Effect = "Allow";
              Action = "s3:*";
              Resource = "arn:aws:s3:::charon-${uuid}-report-server-logs/*";
            }
          ];
        };
      };
    };
  };
}
