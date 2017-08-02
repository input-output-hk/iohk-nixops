# TODO: get rid of this duplication between config.nix and modules/cardano-node.nix
# XXX: rename this file:  cardano-node-config vs. cardano-nodes-config is CRUEL
with (import ./../lib.nix);

params:
  { pkgs, nodes, ...}: {
    imports = [
      ./common.nix
    ];

    services.cardano-node =
    let
      neighbourNames       = flatten params.static-routes;
      nodeNameToPublicIP   = name: cardanoAttr "publicIP" nodes.${name}.config.services.cardano-node;
      neighbourPairs       = map (n: { name = n; ip = nodeNameToPublicIP n; })
                                 (builtins.trace "${params.name}: role '${params.type}'" neighbourNames);
      ppNeighbour          = n: "${n.name}: ${n.ip}";
      sep                  = ", ";
    in {
      enable     = true;
      nodeName   = params.name;
      type       = params.type;
      nodeIndex  = params.i;
      port       = cconf.nodePort;
      inherit (cconf) enableP2P genesisN slotDuration networkDiameter mpcRelayInterval;
      inherit (cconf) totalMoneyAmount bitcoinOverFlat productionMode systemStart richPoorDistr;
      neighbours = builtins.trace "${params.name}: neighbours: ${concatStringsSep sep (map ppNeighbour neighbourPairs)}"
                                  neighbourPairs;
    };
  }
