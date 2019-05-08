############################################################################
# This is the jobset declaration evaluated by Hydra to dynamically
# generate jobsets.
#
# The arguments for this file come from spec.json.
# So also update that file when you add a repo here.
#
# You may also want to check and update the GitHub notifications list
# in modules/hydra-master-main.nix.
#
# Test this file locally with:
#   jq . < $(nix-build --no-out-link jobsets/default.nix)
#
# See also the Hydra manual:
#   https://github.com/NixOS/hydra/blob/master/doc/manual/declarative-projects.xml
#
############################################################################

{ nixpkgs ? <nixpkgs>
, declInput ? {}

# Paths to JSON files containing PR info fetched from github.
# An example file is ./simple-pr-dummy.json.
, nixopsPrsJSON ? ./simple-pr-dummy.json
, cardanoPrsJSON ? ./simple-pr-dummy.json
, daedalusPrsJSON ? ./simple-pr-dummy.json
, plutusPrsJSON ? ./simple-pr-dummy.json
, logClassifierPrsJSON ? ./simple-pr-dummy.json
, ouroborosNetworkPrsJSON ? ./simple-pr-dummy.json
, iohkMonitoringPrsJSON ? ./simple-pr-dummy.json
, ledgerPrsJSON ? ./simple-pr-dummy.json
, cardanoLedgerSpecsPrsJSON ? ./simple-pr-dummy.json
, shellPrsJSON ? ./simple-pr-dummy.json
, walletPrsJSON ? ./simple-pr-dummy.json
, iohkNixPrsJSON ? ./simple-pr-dummy.json
, haskellNixPrsJSON ? ./simple-pr-dummy.json
}:

let pkgs = import nixpkgs {}; in

with pkgs.lib;

let

  ##########################################################################
  # GitHub repos to make jobsets for.
  # These are processed by the mkRepoJobsets function below.

  repos = {
    cardano-sl = {
      description = "Cardano SL";
      url = "https://github.com/input-output-hk/cardano-sl.git";
      input = "cardano";  # corresponds to argument in cardano-sl/release.nix
      branch = "develop";
      branches = {
        master = "master";
        "1-0" = "release/1.0.x";
        "1-2" = "release/1.2.0";
        "1-3" = "release/1.3.1";
        "2-0" = "release/2.0.0";
        "3-0-1" = "release/3.0.1";
      };
      prs = cardanoPrsJSON;
      prJobsetModifier = withFasterBuild;
      bors = true;
    };

    daedalus = {
      description = "Daedalus Wallet";
      url = "https://github.com/input-output-hk/daedalus.git";
      branch = "develop";
      prs = daedalusPrsJSON;
      bors = true;
    };

    plutus = {
      description = "Plutus Language";
      url = "https://github.com/input-output-hk/plutus.git";
      prs = plutusPrsJSON;
    };

    log-classifier = {
      description = "Log Classifier";
      url = "https://github.com/input-output-hk/log-classifier.git";
      prs = logClassifierPrsJSON;
      bors = true;
    };

    cardano-ledger = {
      description = "Cardano Ledger";
      url = "https://github.com/input-output-hk/cardano-ledger.git";
      branch = "master";
      prs = ledgerPrsJSON;
      bors = true;
    };

    cardano-ledger-specs = {
      description = "Cardano Ledger Specs";
      url = "https://github.com/input-output-hk/cardano-ledger-specs.git";
      branch = "master";
      prs = cardanoLedgerSpecsPrsJSON;
    };

    ouroboros-network = {
      description = "Ouroboros Network";
      url = "https://github.com/input-output-hk/ouroboros-network.git";
      branch = "master";
      prs = ouroborosNetworkPrsJSON;
      bors = true;
    };

    iohk-monitoring = {
      description = "IOHK Monitoring Framework";
      url = "https://github.com/input-output-hk/iohk-monitoring-framework.git";
      branch = "develop";
      prs = iohkMonitoringPrsJSON;
      bors = true;
    };

    iohk-nix = {
      description = "IOHK Common Nix Expressions";
      url = "https://github.com/input-output-hk/iohk-nix.git";
      branch = "master";
      prs = iohkNixPrsJSON;
      bors = true;
    };

    haskell-nix = {
      description = "Haskell.nix Build System";
      url = "https://github.com/input-output-hk/haskell.nix.git";
      branch = "master";
      prs = haskellNixPrsJSON;
    };

    cardano-wallet = {
      description = "Cardano Wallet Backend";
      url = "https://github.com/input-output-hk/cardano-wallet.git";
      branch = "master";
      prs = walletPrsJSON;
    };

    cardano-shell = {
      description = "Cardano Shell";
      url = "https://github.com/input-output-hk/cardano-shell.git";
      branch = "develop";
      prs = shellPrsJSON;
      bors = true;
    };
  };

  ##########################################################################
  # Jobset generation functions

  mkFetchGithub = value: {
    inherit value;
    type = "git";
    emailresponsible = false;
  };

  defaultSettings = {
    enabled = 1;
    hidden = false;
    nixexprinput = "jobsets";
    keepnr = 5;
    schedulingshares = 42;
    checkinterval = 60;
    inputs = {
      nixpkgs = mkFetchGithub "https://github.com/input-output-hk/nixpkgs.git ${nixpkgs-src.rev}";
      jobsets = mkFetchGithub "${iohkOpsURI} master";
    };
    enableemail = false;
    emailoverride = "";
  };

  # Adds an arg which disables optimization for cardano-sl builds
  withFasterBuild = jobset: jobset // {
    inputs = (jobset.inputs or { }) // {
      fasterBuild = { type = "boolean"; emailresponsible = false; value = "true"; };
    };
  };

  # Use to put Bors jobs at the front of the build queue.
  highPrio = jobset: jobset // {
    schedulingshares = 420;
  };

  # Removes PRs which have any of the labels in ./pr-excluded-labels.nix
  exclusionFilter = let
    excludedLabels = import ./pr-excluded-labels.nix;
    justExcluded = filter (label: (elem label.name excludedLabels));
    isEmpty = ls: length ls == 0;
  in
    filterAttrs (_: prInfo: isEmpty (justExcluded (prInfo.labels or [])));

  loadPrsJSON = path: exclusionFilter (builtins.fromJSON (builtins.readFile path));

  # Make jobset for a project default build
  mkJobset = { name, description, url, input, branch }: let
    jobset = defaultSettings // {
      nixexprpath = "release.nix";
      nixexprinput = input;
      inherit description;
      inputs = {
        "${input}" = mkFetchGithub "${url} ${branch}";
      };
    };
  in
    nameValuePair name jobset;

  # Make jobsets for extra project branches (e.g. release branches)
  mkJobsetBranches = { name, description, url, input }:
    mapAttrsToList (suffix: branch:
      mkJobset { name = "${name}-${suffix}"; inherit description url input branch; });

  # Make a jobset for a GitHub PRs
  mkJobsetPR = { name, input, modifier }: num: info: {
    name = "${name}-pr-${num}";
    value = defaultSettings // modifier {
      description = "PR ${num}: ${info.title}";
      nixexprinput = input;
      nixexprpath = "release.nix";
      inputs = {
        "${input}" = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
      };
    };
  };

  # Load the PRs json and make a jobset for each
  mkJobsetPRs = { name, input, modifier, prs }:
    mapAttrsToList
      (mkJobsetPR { inherit name input modifier; })
      (loadPrsJSON prs);

  # Add two extra jobsets for the bors staging and trying branches
  mkJobsetBors = { name, ... }@args: let
    jobset = branch: (mkJobset (args // { inherit branch; })).value;
  in [
    (nameValuePair "${name}-bors-staging" (highPrio (jobset "bors/staging")))
    (nameValuePair "${name}-bors-trying" (jobset "bors/trying"))
  ];

  # Make all the jobsets for a project repo, according to the "repos" spec above.
  mkRepoJobsets = let
    mkRepo = name: info: let
      input = info.input or name;
      branch = info.branch or "master";
      params = { inherit name input; inherit (info) description url; };
      prJobsetModifier = info.prJobsetModifier or (s: s);
    in
      [ (mkJobset (params // { inherit branch; })) ] ++
      (mkJobsetBranches params (info.branches or {})) ++
      (mkJobsetPRs { inherit name input; inherit (info) prs; modifier = prJobsetModifier; }) ++
      (optionals (info.bors or false) (mkJobsetBors params));
  in
    rs: listToAttrs (concatLists (mapAttrsToList mkRepo rs));


  ##########################################################################
  # iohk-ops structure is slightly different

  iohkOpsURI = "https://github.com/input-output-hk/iohk-ops.git";
  nixpkgs-src = builtins.fromJSON (builtins.readFile ./../nixpkgs-src.json);
  mkNixops = nixopsBranch: nixpkgsRev: {
    nixexprpath = "jobsets/cardano.nix";
    description = "IOHK-Ops";
    inputs = {
      nixpkgs = mkFetchGithub "https://github.com/input-output-hk/nixpkgs.git ${nixpkgsRev}";
      jobsets = mkFetchGithub "${iohkOpsURI} ${nixopsBranch}";
      nixops = mkFetchGithub "https://github.com/NixOS/NixOps.git tags/v1.5";
    };
  };
  makeNixopsPR = num: info: {
    name = "iohk-ops-pr-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprpath = "jobsets/cardano.nix";
      inputs = {
        nixpkgs = mkFetchGithub "https://github.com/input-output-hk/nixpkgs.git ${nixpkgs-src.rev}";
        jobsets = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
        nixops = mkFetchGithub "https://github.com/NixOS/NixOps.git tags/v1.5";
      };
    };
  };
  nixopsPrJobsets = listToAttrs (mapAttrsToList makeNixopsPR (loadPrsJSON nixopsPrsJSON));

  ##########################################################################
  # Jobsets which don't fit into the regular structure

  extraJobsets = mapAttrs (name: settings: defaultSettings // settings) ({
    # Provides cached build projects for PR builds with -O0
    no-opt-cardano-sl = withFasterBuild mainJobsets.cardano-sl;

    # iohk-ops (this repo)
    iohk-ops = mkNixops "master" nixpkgs-src.rev;
    iohk-ops-bors-staging = highPrio (mkNixops "bors-staging" nixpkgs-src.rev);
    iohk-ops-bors-trying = mkNixops "bors-trying" nixpkgs-src.rev;
    rust-cardano = (mkJobset {
      name = "rust-cardano";
      input = "rust-cardano";
      description = "Cardano Rust Library";
      url = "https://github.com/input-output-hk/rust-cardano.git";
      branch = "master";
    }).value;
  } // nixopsPrJobsets);

  ##########################################################################
  # The final jobsets spec as JSON

  mainJobsets = mkRepoJobsets repos;
  jobsetsAttrs = mainJobsets // extraJobsets;
in {
  jobsets = pkgs.runCommand "spec.json" {} ''
    cat <<EOF
    ${builtins.toJSON declInput}
    EOF
    cp ${pkgs.writeText "spec.json" (builtins.toJSON jobsetsAttrs)} $out
  '';
}
