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
      nodeByName           = x: let xs = filter (n: n.config.services.cardano-node.enable   == true
                                                 && n.config.services.cardano-node.nodeName == x) (attrValues nodes);
                                in if xs != [] then builtins.elemAt xs 0
                                   else throw "nodeById: no node with name '${toString x}'";
      nodePublicIP         = n: let ip = n.config.services.cardano-node.publicIP;
                                in if ip != null then ip
                                   else throw "nodePublicIP: node '${n.config.services.cardano-node.nodeName}' has no public IP configured.";
      nodeNameToPublicIP   = name: nodePublicIP (nodeByName name);
      neighbourPairs       = map (n: { name = n; ip = nodeNameToPublicIP n; })
                                 (builtins.trace "${params.name}: role '${params.type}'" neighbourNames);
      ppNeighbour          = n: "${n.name}: ${n.ip}";
      sep                  = ", ";
    in {
      enable     = true;
      nodeName   = params.name;
      nodeIndex  = params.i;
      port       = cconf.nodePort;
      inherit (cconf) enableP2P genesisN slotDuration networkDiameter mpcRelayInterval;
      inherit (cconf) totalMoneyAmount bitcoinOverFlat productionMode systemStart richPoorDistr;
      neighbours = builtins.trace "${params.name}: neighbours: ${concatStringsSep sep (map ppNeighbour neighbourPairs)}"
                                  neighbourPairs;
    };
  }
