{ accessKeyId, nodes ? 1 , walletsPerNode ? 1
, region ? "eu-central-1"
, topologyFile, systemStart }:

with import ../lib.nix;
let
  iohkpkgs = import ../. {};
  params = index: {
    walletListen = "127.0.0.1:${toString (8090 + index)}";
    ekgListen = "127.0.0.1:${toString (8000 + index)}";
    environment = "override";
    confKey = "bench";
    inherit topologyFile;
    extraParams = "--system-start ${toString systemStart}";
  };
  mkService = index: {
    users.users."cardano-node-${toString index}" = {
      isNormalUser = true;
    };
    systemd.services."cardano-node-${toString index}" = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "cardano-node-${toString index}";
        WorkingDirectory = "/home/cardano-node-${toString index}";
        ExecStart = "${iohkpkgs.connectScripts.mainnetWallet.override (params index) }";
      };
    };
  };
  mkNode = index: {
    name = "edgenode-${toString index}";
    value = { resources, ... }: {
      imports = map mkService (range 1 walletsPerNode);
      deployment = {
        targetEnv = "ec2";
        ec2 = {
          inherit region accessKeyId;
          instanceType = mkDefault "t2.large";
          keyPair = resources.ec2KeyPairs.edgekey;
          ebsInitialRootDiskSize = 100;
        };
      };
    };
  };
in {
  resources.ec2KeyPairs.edgekey = {
    inherit region accessKeyId;
  };
} // listToAttrs (map mkNode (range 1 nodes))
