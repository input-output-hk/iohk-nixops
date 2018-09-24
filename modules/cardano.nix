# XXX: rename this file:  cardano-node-config vs. cardano-nodes-config is CRUEL
with import ../lib.nix;

{ pkgs, nodes, config, resources, options, ...}:

  let
    assetLockFile = ../static/asset-locked-addresses.txt;
    nodeNameToPublicIP   = name: let ip = nodes.${name}.config.services.cardano-node.publicIP;
                                 in if ip == null then "" else ip;
    neighbourPairs       = map (n: { name = n; ip = nodeNameToPublicIP n; })
                               (builtins.trace "${config.params.name}: role '${config.params.nodeType}'" config.params.peers);
    ppNeighbour          = n: "${n.name}: ${n.ip}";
    sep                  = ", ";
    cfg                  = config.services.cardano-node;
  in {
    imports = [
      ./cardano-service.nix
      ./cardano-base.nix
      ./globals.nix
    ];

    networking.extraHosts =
    let hostList = if config.services.cardano-node.enable == false then []
                   else
                   neighbourPairs
                   ++ (map (x:
                        { name = x;
                          ip   = nodeNameToPublicIP x; })
                        (attrNames config.global.nodeMap))
                   ++ (if !(hasAttr "publicIP" config.services.cardano-node) then []
                       else [ { name = config.params.name;
                                ip   = nodeNameToPublicIP config.params.name; } ]);
    in
    ''
    ${concatStringsSep "\n" (map (host: "${toString host.ip} ${host.name}.cardano") hostList)}
    '';

    # TODO, merge with the monitor in modules/report-server.nix
    services.dd-agent.processMonitor = if config.params.typeIsExplorer then "cardano-explorer" else "cardano-node-simple";

    services.cardano-node = {
      enable         = true;
      nodeName       = config.params.name;
      nodeIndex      = config.params.i;
      relayIndex     = params.relayIndex;
      port           = config.params.port;
      enablePolicies = config.global.environment == "benchmark";
      topologyYaml   =
         if !config.params.typeIsExplorer
         then config.global.topologyYaml
         else
           let relayAddressSpecs =
             if (config.global.environment == "development" || config.global.environment == "benchmark")
             then map (name: { addrType = "addr"; addr = nodeNameToPublicIP name; })
                      (map (x: x.name) config.global.relays)
             else map (idx:  { addrType = "host"; addr = "cardano-node-${toString idx}.${config.global.dnsDomainname}"; })
                      (range 0 (config.global.nRelays - 1));
           in pkgs.writeText "topology-explorer.yaml" ''
wallet:
  relays: [[${concatStringsSep ", " (map ({ addrType, addr }: "{\"${addrType}\": \"${addr}\", \"port\": ${toString config.params.port}}")
                                         relayAddressSpecs)}]]
  valency: 3
  fallbacks: 2
           '';
      systemStart = params.systemStart;
      jsonLog = (config.global.environment == "benchmark");
      nodeType    = config.params.nodeType;
      neighbours = builtins.trace "${config.params.name}: neighbours: ${concatStringsSep sep (map ppNeighbour neighbourPairs)}"
                                  neighbourPairs;
      publicIP = if options.networking.publicIPv4.isDefined then config.networking.publicIPv4 else null;
      privateIP = if options.networking.privateIPv4.isDefined then config.networking.privateIPv4 else "0.0.0.0";
      statsdServer = "127.0.0.1:8125";
    } // (optionalAttrs (config.params.typeIsCore && (builtins.pathExists assetLockFile)) { inherit assetLockFile; });
    deployment.keys =
      (optionalAttrs (config.params.typeIsCore && cfg.productionMode)
        (let keyfile = "key${toString config.params.i}.sk";
         in {
           "key${toString config.params.i}" = builtins.trace (config.params.name + ": using " + keyfile) {
             keyFile = ./. + "/../keys/${keyfile}";
             user = "cardano-node";
           };}));
  }
