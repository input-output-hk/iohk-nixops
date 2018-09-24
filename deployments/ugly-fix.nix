{
  hydra-build-slave-1 = { resources, ... }: {
    deployment.ec2.keyPair = resources.ec2KeyPairs.cardano-test-eu-central;
  };
  hydra-build-slave-2 = { resources, ... }: {
    deployment.ec2.keyPair = resources.ec2KeyPairs.cardano-keypair-IOHK-eu-central-1;
  };
  hydra-build-slave-3 = { resources, ... }: {
    deployment.ec2.keyPair = resources.ec2KeyPairs.cardano-keypair-IOHK-eu-central-1;
  };
  hydra-build-slave-4 = { resources, ... }: {
    deployment.ec2.keyPair = resources.ec2KeyPairs.cardano-keypair-IOHK-eu-central-1;
  };
  hydra = { resources, ... }: {
    deployment.ec2.keyPair = resources.ec2KeyPairs.cardano-test-eu;
  };

  resources.ec2KeyPairs.cardano-test-eu = {
    accessKeyId = "cardano-deployer";
    region = "eu-central-1";
  };
  resources.ec2KeyPairs.cardano-test-eu-central = {
    accessKeyId = "cardano-deployer";
    region = "eu-central-1";
  };
}
