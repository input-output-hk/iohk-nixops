{ accessKeyId, ... }:

with (import ./../lib.nix);
{
  resources = {
    ec2KeyPairs = ec2KeyPairs accessKeyId;
  };
}
