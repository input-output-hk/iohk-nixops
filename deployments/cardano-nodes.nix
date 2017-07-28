{ accessKeyId, ... }:

with (import ./../lib.nix);
let
  nodeConfig = import ./../modules/cardano-node-config.nix;
  nodes = import ./cardano-nodes-config.nix { inherit accessKeyId; };
in {
  network.description = "Cardano SL";
} // (mkNodesUsing nodeConfig nodes)
