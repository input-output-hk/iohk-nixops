# To interact with this file:
# nix-repl lib.nix

let
  sources       = import ./nix/sources.nix;
  goguenSources = import ./goguen/nix/sources.nix;
  iohkNix       = import sources.iohk-nix { application = "iohk-ops"; nixpkgsOverride = import ./fetch-nixpkgs.nix; };
  iohkNixGoguen = import goguenSources.iohk-nix { nixpkgsJsonOverride = ./goguen/pins/nixpkgs-src.json
                            # TODO after updating iohk-nix: instead of nixpkgsJsonOverride: sourcesOverride = { inherit (goguenSources) nixpkgs }
                            ; config = { allowUnfree = true; }
                            ; };
  goguenNixpkgs = iohkNixGoguen.nixpkgs;

  pinFile       = dir: name: dir + "/${name}-src.json";
  readPin       = dir: name: builtins.fromJSON (builtins.readFile (pinFile dir name));
  readPinTraced = dir: name: let json = builtins.readFile (pinFile dir name); in
                             builtins.fromJSON (builtins.trace json json);
  pinIsPrivate  = dir: name: let pin = builtins.fromJSON (builtins.readFile (pinFile dir name));
                             in pin.url != builtins.replaceStrings ["git@github.com"] [""] pin.url;
  addPinName = name: pin: pin // { name = name+"-git-${pin.rev}"; };
  getPinFetchgit = dir: name: removeAttrs     (readPin dir name)  ["ref"];
  getPinFetchGit = dir: name: addPinName name (readPin dir name); ## 'submodules' to be removed later
  fetchGitPin = name: pinJ:
    builtins.fetchGit (pinJ // { name = name; });

  ## repoSpec                = RepoSpec { name :: String, subdir :: FilePath, src :: Drv }
  ## fetchGitWithSubmodules :: Name -> Drv -> Map String RepoSpec -> Drv
  fetchGitWithSubmodules = mainName: mainRev: mainSrc: subRepos:
    with builtins; with pkgs;
    let subRepoCmd = repo: ''
        chmod -R u+w $(dirname $out/${repo.subdir})
        rmdir $out/${repo.subdir}
        cp -R  ${repo.src} $out/${repo.subdir}
        '';
        cmd = ''

        cp -R ${mainSrc} $out

        '' + concatStringsSep "\n" (map subRepoCmd (attrValues subRepos));
    in runCommand "fetchGit-composite-src-${mainName}-${mainRev}" { buildInputs = []; } cmd;

  fetchGitPinWithSubmodules = pinRoot: name: { submodules ? {}, ... }@pin:
    let fetchSubmodule = subName: subDir: { subdir = subDir; src = pkgs.fetchgit (getPinFetchgit pinRoot subName); };
    in fetchGitWithSubmodules name pin.rev
       (builtins.fetchGit (removeAttrs pin ["submodules"]))
       (lib.mapAttrs fetchSubmodule submodules);

  ## Depending on whether the repo is private (URL has 'git@github' in it), we need to use fetchGit*
  fetchPinAuto = pinRoot: name:
    if pinIsPrivate pinRoot name
    then fetchGitPinWithSubmodules pinRoot name (getPinFetchGit pinRoot name)
    else pkgs.fetchgit                          (getPinFetchgit pinRoot name);

  # nixpkgs can be overridden for debugging purposes by setting
  # NIX_PATH=custom_nixpkgs=/path/to/nixpkgs
  pkgs = iohkNix.pkgs;
  lib = pkgs.lib;
  fetchProjectPackages = name: host: pinRoot: revOverride: args:
    let
      src = let try = builtins.tryEval host;
        in if try.success
           then builtins.trace "using search host <${name}>" try.value
           else fetchPinAuto pinRoot name;
      src-phase2 = let
        localOverride = {
          ### XXX: not really workable right now, for obvious reasons.  Left for uniformity with CSL definition above/future refactoring.
          outPath = builtins.fetchTarball "https://github.com/input-output-hk/${name}/archive/${revOverride}.tar.gz";
          rev = revOverride;
        };
        in if (revOverride != null) then localOverride else src;
      pkgs = import src-phase2 ({
        } // lib.optionalAttrs (src-phase2 ? rev) {
          gitrev = src-phase2.rev;
        });
    in pkgs;
  javaOverrideNixpkgsConfig = {
    overlays = [ oracleJdkOverlay ];
    config.allowUnfree = true;
  };
  oracleJdkOverlay =  self : super: {
    oraclejdk8 = super.callPackage ./goguen/jdk-override/jdk8cpu-linux.nix {
      installjdk = true;
      pluginSupport = false;
      licenseAccepted = true;
    };
  };
  graalvm8 = (import iohkNixGoguen.nixpkgs javaOverrideNixpkgsConfig).graalvm8;
in lib // (rec {
  inherit (iohkNix) nixpkgs cardanoLib;
  inherit fetchProjectPackages pkgs graalvm8;
  inherit sources iohkNix iohkNixGoguen goguenNixpkgs;
  inherit fetchPinAuto fetchGitWithSubmodules readPin;

  makeCreds = service: default:
    if
      (builtins.pathExists (./static + "/${service}-creds.nix"))
    then (import (./static + "/${service}-creds.nix"))
    else default;

  mkMkUplink = { central, subnet, endpoint }: n: path: { lib, config, ... }: {
    deployment.keys."uplink.wgprivate" = {
      destDir = "/etc/wireguard";
      keyFile = path;
    };
    services.monitoring-exporters = {
      graylogHost = lib.mkForce "${central}:5044";
      ownIp = lib.mkForce "${subnet}.${toString n}";
    };
    boot.extraModulePackages = [ config.boot.kernelPackages.wireguard ];
    networking.wireguard.interfaces.wg0 = {
      ips = [ "${subnet}.${toString n}/32" ];
      listenPort = 51820;
      privateKeyFile = "/etc/wireguard/uplink.wgprivate";
      peers = [
        { allowedIPs = [ "${central}/32" ]; publicKey = lib.strings.removeSuffix "\n" (builtins.readFile ./static/monitoring.wgpublic); endpoint = endpoint; }
      ];
    };
  };

  ## nodeElasticIP :: Node -> EIP
  nodeElasticIP = node:
    { name = "${node.name}-ip";
      value = { inherit (node) region accessKeyId; };
    };
  nodeDryRunnablePrivateIP = node: if node.options.networking.privateIPv4.isDefined then node.config.networking.privateIPv4 else "DRYRUN-PLACEHOLDER";
  nodeDryRunnablePublicIP  = node: if node.options.networking.publicIPv4.isDefined  then node.config.networking.publicIPv4  else "DRYRUN-PLACEHOLDER";

  centralRegion = "eu-central-1";
  centralZone   = "eu-central-1b";

  ## nodesElasticIPs :: Map NodeName Node -> Map EIPName EIP
  nodesElasticIPs = nodes: lib.flip lib.mapAttrs' nodes
    (name: node: nodeElasticIP node);

  resolveSGName = resources: name: resources.ec2SecurityGroups.${name};

  orgRegionKeyPairName = org: region: "cardano-keypair-${org}-${region}";

  traceF   = f: x: builtins.trace                         (f x)  x;
  traceSF  = f: x: builtins.trace (builtins.seq     (f x) (f x)) x;
  traceDSF = f: x: builtins.trace (builtins.deepSeq (f x) (f x)) x;

  # Parse peers from a file
  #
  # > peersFromFile ./peers.txt
  # ["ip:port/dht" "ip:port/dht" ...]
  peersFromFile = file: lib.splitString "\n" (builtins.readFile file);

  # Given a list of NixOS configs, generate a list of peers (ip/dht mappings)
  genPeersFromConfig = configs:
    let
      f = c: "${c.networking.publicIPv4}:${toString c.services.cardano-node.port}";
    in map f configs;

  # modulo operator
  # mod 11 10 == 1
  # mod 1 10 == 1
  mod = base: int: base - (int * (builtins.div base int));

  # Removes files within a Haskell source tree which won't change the
  # result of building the package.
  # This is so that cached build products can be used whenever possible.
  # It also applies the lib.cleanSource filter from nixpkgs which
  # removes VCS directories, emacs backup files, etc.
  cleanSourceTree = src:
    if lib.canCleanSource src
      then lib.cleanSourceWith {
        filter = with pkgs.stdenv;
          name: type: let baseName = baseNameOf (toString name); in ! (
            # Filter out cabal build products.
            baseName == "dist" || baseName == "dist-newstyle" ||
            baseName == "cabal.project.local" ||
            lib.hasPrefix ".ghc.environment" baseName ||
            # Filter out stack build products.
            lib.hasPrefix ".stack-work" baseName ||
            # Filter out files which are commonly edited but don't
            # affect the cabal build.
            lib.hasSuffix ".nix" baseName
          );
        src = lib.cleanSource src;
      } else src;

} // (with (import ./lib/ssh-keys.nix { inherit lib; }); rec {
  #
  # Access
  #
  inherit devOps csl-developers;

  devOpsKeys = allKeysFrom devOps;
  testnetKeys = allKeysFrom devOps ++ allKeysFrom testnet;
  devKeys = devOpsKeys ++ allKeysFrom csl-developers;
  mantisOpsKeys = allKeysFrom devOps ++ allKeysFrom mantis-devOps;

  # Access to login to CI infrastructure
  ciInfraKeys = devOpsKeys ++ allKeysFrom { inherit (csl-developers) angerman; };

  buildSlaveKeys = {
    macos = devOpsKeys ++ allKeysFrom remoteBuilderKeys;
    linux = remoteBuilderKeys.hydraBuildFarm;
  };

}))
