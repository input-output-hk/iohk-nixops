# XXX: rename this file:  cardano-node-config vs. cardano-nodes-config is CRUEL
with (import ./../lib.nix);

globals: imports: params:
  { pkgs, nodes, config, resources, options, ...}:
  let
    nodeNameToPublicIP   = name: let ip = nodes.${name}.config.services.cardano-node.publicIP;
                                 in if ip == null then "" else ip;
    neighbourPairs       = map (n: { name = n; ip = nodeNameToPublicIP n; })
                               (builtins.trace "${params.name}: role '${params.nodeType}'" params.peers);
    ppNeighbour          = n: "${n.name}: ${n.ip}";
    sep                  = ", ";
    cfg                  = config.services.cardano-node;
  in {
    imports = [
      ./common.nix
      ./amazon-base.nix
      ./network-wide.nix
      (import ./cardano-service.nix globals params)
    ] ++ map (path: import path globals params) imports;

    global.organisation = params.org;

    services.dnsmasq.enable = true;
    services.dnsmasq.servers = [ "127.0.0.1" ];

    # TODO: DEVOPS-8
    #deployment.ec2.ami = (import ./amis.nix).${config.deployment.ec2.region};
    deployment.ec2.region         = mkForce params.region;
    deployment.ec2.zone           = mkForce params.zone;
    deployment.ec2.accessKeyId    = params.accessKeyId;
    deployment.ec2.keyPair        = resources.ec2KeyPairs.${params.keyPairName};
    deployment.ec2.securityGroups =
      with params;
      let sgNames =
           optionals typeIsExplorer              [ "allow-to-explorer-${params.region}" ]
        ++ optionals typeIsCore                  [ "allow-cardano-static-peers-${params.name}-${params.region}-${params.org}" ]
        ++ optionals typeIsRelay                 [ "allow-kademlia-public-udp-${params.region}"
                                                   "allow-cardano-public-tcp-${params.region}" ]
        ++ optionals config.global.enableEkgWeb  [ "allow-ekg-public-tcp-${params.region}-${params.org}" ];
      in map (resolveSGName resources)
             (if config.global.omitDetailedSecurityGroups
              then [ "allow-all-${params.region}-${params.org}" ]
              else sgNames);

    networking.extraHosts =
    let hostList = if config.services.cardano-node.enable == false then []
                   else
                   neighbourPairs
                   ++ (map (x:
                        { name = x;
                          ip   = nodeNameToPublicIP x; })
                        (attrNames globals.nodeMap))
                   ++ (if !(hasAttr "publicIP" config.services.cardano-node) then []
                       else [ { name = params.name;
                                ip   = nodeNameToPublicIP params.name; } ]);
    in
    ''
    ${concatStringsSep "\n" (map (host: "${toString host.ip} ${host.name}.cardano") hostList)}
    '';

    services.dd-agent.processConfig = ''
    init_config:

    instances:
    - name:            ${if params.typeIsExplorer then "cardano-explorer" else "cardano-node-simple"}
      search_string: ['${if params.typeIsExplorer then "cardano-explorer" else "cardano-node-simple"}']
      exact_match: True
      thresholds:
        critical: [1, 1]
    '';

    services.cardano-node = {
      enable      = true;
      nodeName    = params.name;
      nodeIndex   = params.i;
      relayIndex  = params.relayIndex;
      port        = params.port;
      genesis     = globals.genesis;
      topologyYaml      =
         if !params.typeIsExplorer
         then globals.topologyYaml
         else
           let relayAddressSpecs =
             if globals.environment == "development"
             then map (name: { addrType = "addr"; addr = nodeNameToPublicIP name; })
                      (map (x: x.name) globals.relays)
             else map (idx:  { addrType = "host"; addr = "cardano-node-${toString idx}.${config.global.dnsDomainname}"; })
                      (range 0 (globals.nRelays - 1));
           in pkgs.writeText "topology-explorer.yaml" ''
wallet:
  relays: [[${concatStringsSep ", " (map ({ addrType, addr }: "{\"${addrType}\": \"${addr}\", \"port\": ${toString params.port}}")
                                         relayAddressSpecs)}]]
  valency: 3
  fallbacks: 2
           '';
      systemStart = params.systemStart;
      nodeType    = params.nodeType;
      neighbours = builtins.trace "${params.name}: neighbours: ${concatStringsSep sep (map ppNeighbour neighbourPairs)}"
                                  neighbourPairs;
      publicIP = if options.networking.publicIPv4.isDefined then config.networking.publicIPv4 else null;
      privateIP = if options.networking.privateIPv4.isDefined then config.networking.privateIPv4 else "0.0.0.0";
      statsdServer = "127.0.0.1:8125";
    };

    deployment.keys =
      (optionalAttrs (params.typeIsCore && cfg.productionMode)
        (let keyfile = "key${toString params.i}.sk";
         in {
           "key${toString params.i}" = builtins.trace (params.name + ": using " + keyfile) {
             keyFile = ./. + "/../keys/${keyfile}";
             user = "cardano-node";
           };}));
  }
