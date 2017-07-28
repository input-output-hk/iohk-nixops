{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeAWSConfig = (import ./../modules/cardano-node-aws.nix) { inherit accessKeyId; };
  nodes         = import ./cardano-nodes-config.nix { inherit accessKeyId; };
in
  mkNodesUsing nodeAWSConfig nodes
