{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeAWSConfig = (import ./../modules/cardano-node-aws.nix) { inherit accessKeyId; };
  explorer      = import ./cardano-explorer-config.nix;
in
  mkNodesUsing nodeAWSConfig explorer
