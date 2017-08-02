{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeArgs    = (import ./cardano-nodes-config.nix         { inherit accessKeyId; }).nodeArgs;
  nodeTgtConf = (import ./../modules/cardano-node-aws.nix) { inherit accessKeyId; };
in
  mkNodesUsing nodeTgtConf nodeArgs
