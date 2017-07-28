{ accessKeyId, ... }:

with (import ./../lib.nix);

let clusterSpec    = (builtins.fromJSON (builtins.readFile ./../cluster.nix));
    clusterNodes   = clusterSpec.nodes;  # Strip the outer "nodes:" shell of cluster.yaml
    nodeList       = builtins.sort (l: r: l.name < r.name)
                                   (mapAttrsToList (k: v: { name = k; value = v; }) clusterNodes);
    indexedNodes   = imap (i: x: with x.value;
          { name = x.name; value = {
                               i = i - 1;
                            name = x.name; # This is an important identity, let's not break it.
                          region = region;
                            type = type;
                   static-routes = if builtins.hasAttr "static-routes" x.value then x.value.static-routes else [];
                             }; } ) nodeList;
    # Canonical node parameter format is:
    #   i             :: Int
    #   region        :: String
    #   type          :: String             -- one of: 'core', 'relay'
    #   static-routes :: [[NodeId, NodeId]] -- here we go, TupleList..
    canonicalNodes = builtins.listToAttrs indexedNodes;
in
  canonicalNodes
