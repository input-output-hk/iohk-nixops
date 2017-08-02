{ accessKeyId, ... }:

with (import ./../lib.nix);

let clusterSpec   = (builtins.fromJSON (builtins.readFile ./../cluster.nix)).nodes; # Strip the outer "nodes:" shell of cluster.yaml
    clusterList   = builtins.sort (l: r: l.name < r.name)
                                   (mapAttrsToList (k: v: { name = k; value = v; }) clusterSpec);
    regionList    = unique (map (n: n.value.region) clusterList);
    indexed       = imap (n: x:
           let spec = x.value; in
           { name = x.name; value = rec {
                                i = n - 1;
                             name = x.name; # This is an important identity, let's not break it.
                           region = spec.region;
                             type = spec.type;
                    static-routes = if builtins.hasAttr "static-routes" spec then spec.static-routes else [];
                         sg-names = if      spec.type == "other" then
                                      [ "allow-open-${region}" ]
                                    else if spec.type == "core"  then
                                      [ "allow-ssh-${region}"
                                        "allow-cardano-static-peers-${name}-${region}" ]
                                    else if spec.type == "relay" then
                                      [ "allow-ssh-${region}"
                                        "allow-kademlia-public-udp-${region}"
                                        "allow-cardano-public-tcp-${region}" ]
                                    else throw "While computing EC2 SGs: unhandled cardano-node type: '${type}'";
                             }; } ) clusterList;
    byName        = name: let xs = filter (n: n.name == name) indexed;
                          in if xs != [] then builtins.elemAt xs 0
                             else throw "No indexedNode by name '${name}'.";
    # Canonical node parameter format is:
    #   i             :: Int
    #   region        :: String
    #   type          :: String               -- one of: 'core', 'relay'
    #   static-routes :: [['nodeId, 'nodeId]] -- here we go, TupleList..
    canonical       = builtins.listToAttrs indexed;
    cores           = filter (x: x.value.type == "core") indexed;
    ##
    ##
    regionSGNames = region:
        [ "allow-open-${region}"
          "allow-ssh-${region}"
          "allow-kademlia-public-udp-${region}"
          "allow-cardano-public-tcp-${region}"
        ];
    regionSGs      = nodePort: region: {
        "allow-open-${region}" = {
          inherit region accessKeyId;
          description = "Everything goes";
          rules = [{
            protocol = "-1"; # All traffic
            sourceIp = "0.0.0.0/0";
            fromPort = 0;
            toPort   = 65535;
          }];
        };
        "allow-ssh-${region}" = {
          inherit region accessKeyId;
          description = "SSH";
          rules = [{
            fromPort = 22;
            toPort   = 22;
            sourceIp = "0.0.0.0/0"; # TODO: move ssh to use $SMART_GEN_IP
          }];
        };
        "allow-kademlia-public-udp-${region}" = {
          inherit region accessKeyId;
          description = "Kademlia UDP public";
          rules = [{
            protocol = "17"; # UDP
            sourceIp = "0.0.0.0/0";
            fromPort = 1024;
            toPort   = 65535;
          }];
        };
        "allow-cardano-public-tcp-${region}" = {
          inherit region accessKeyId;
          description = "Cardano TCP public";
          rules = [{
            fromPort = nodePort;
            toPort   = nodePort;
            sourceIp = "0.0.0.0/0";
          }];
        };
      };
    coreSGNames = core:
        [ "allow-cardano-static-peers-${core.name}-${core.value.region}" ];
    coreSGs     = nodePort: ips: core:
      let neighbourNames = flatten core.value.static-routes;
          neighbours = map byName neighbourNames;
          neigh'rule =
          neigh:
          let
            ip = ips."nodeip${toString neigh.value.i}";
          in {
              fromPort = nodePort;
              toPort   = nodePort;
              sourceIp = ip;
            };
      in {
        "allow-cardano-static-peers-${core.name}-${core.value.region}" = {
          inherit accessKeyId;
          region = core.value.region;
          description = "Cardano TCP static peers of ${core.name}";
          rules = map neigh'rule neighbours;
        };
      };
    securityGroupNames =
     (    concatMap  regionSGNames                             regionList
      ++  concatMap  coreSGNames                               cores
     );
    elasticIPsSecurityGroups =
     elasticIPs:
     (fold (x: y: x // y) {}
     (    map       (regionSGs     cconf.nodePort)             regionList
      ++  map       (coreSGs       cconf.nodePort elasticIPs)  cores
     ));
in
{
  nodeArgs           = canonical;
  securityGroupNames = securityGroupNames;
  securityGroups     = elasticIPsSecurityGroups;
}
