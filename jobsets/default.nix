{ nixopsPrsJSON ? ./simple-pr-dummy.json
, cardanoPrsJSON ? ./simple-pr-dummy.json
, daedalusPrsJSON ? ./simple-pr-dummy.json
, nixpkgs ? <nixpkgs>
, declInput ? {}
, handleCardanoPRs ? true
}:

# Followed by https://github.com/NixOS/hydra/pull/418/files

let
  nixopsPrs = builtins.fromJSON (builtins.readFile nixopsPrsJSON);
  cardanoPrs = builtins.fromJSON (builtins.readFile cardanoPrsJSON);
  daedalusPrs = builtins.fromJSON (builtins.readFile daedalusPrsJSON);

  iohkNixopsUri = "https://github.com/input-output-hk/iohk-nixops.git";
  mkFetchGithub = value: {
    inherit value;
    type = "git";
    emailresponsible = false;
  };
  nixpkgs-src = builtins.fromJSON (builtins.readFile ./../nixpkgs-src.json);
  pkgs = import nixpkgs {};
  defaultSettings = {
    enabled = 1;
    hidden = false;
    nixexprinput = "jobsets";
    keepnr = 5;
    schedulingshares = 42;
    checkinterval = 60;
    inputs = {
      nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgs-src.rev}";
      jobsets = mkFetchGithub "${iohkNixopsUri} master";
    };
    enableemail = false;
    emailoverride = "";
  };
  mkNixops = nixopsBranch: nixpkgsRev: {
    nixexprpath = "jobsets/cardano.nix";
    description = "IOHK-nixops";
    inputs = {
      nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgsRev}";
      jobsets = mkFetchGithub "${iohkNixopsUri} ${nixopsBranch}";
      nixops = mkFetchGithub "https://github.com/NixOS/NixOps.git tags/v1.5";
    };
  };
  makeNixopsPR = num: info: {
    name = "iohk-nixops-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprpath = "jobsets/cardano.nix";
      inputs = {
        nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgs-src.rev}";
        jobsets = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
        nixops = mkFetchGithub "https://github.com/NixOS/NixOps.git tags/v1.5";
      };
    };
  };
  mkCardano = cardanoBranch: nixpkgsRev: {
    nixexprpath = "release.nix";
    nixexprinput = "cardano";
    description = "Cardano SL";
    inputs = {
      cardano = mkFetchGithub "https://github.com/input-output-hk/cardano-sl.git ${cardanoBranch}";
      nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgsRev}";
    };
  };
  makeCardanoPR = num: info: {
    name = "cardano-pr-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprinput = "cardano";
      nixexprpath = "release.nix";
      inputs = {
        nixpkgs = mkFetchGithub "https://github.com/NixOS/nixpkgs.git ${nixpkgs-src.rev}";
        cardano = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
      };
    };
  };
  mkDaedalus = daedalusBranch: {
    nixexprpath = "release.nix";
    nixexprinput = "daedalus";
    description = "Daedalus Wallet";
    inputs = {
      daedalus = mkFetchGithub "https://github.com/input-output-hk/daedalus.git ${daedalusBranch}";
    };
  };
  makeDaedalusPR = num: info: {
    name = "daedalus-pr-${num}";
    value = defaultSettings // {
      description = "PR ${num}: ${info.title}";
      nixexprinput = "daedalus";
      nixexprpath = "release.nix";
      inputs = {
        daedalus = mkFetchGithub "${info.base.repo.clone_url} pull/${num}/head";
      };
    };
  };
  nixopsPrJobsets = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeNixopsPR nixopsPrs);
  cardanoPrJobsets = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeCardanoPR cardanoPrs);
  daedalusPrJobsets = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeDaedalusPR daedalusPrs);
  mainJobsets = with pkgs.lib; mapAttrs (name: settings: defaultSettings // settings) (rec {
    cardano-sl = mkCardano "develop" nixpkgs-src.rev;
    cardano-sl-master = mkCardano "master" nixpkgs-src.rev;
    cardano-sl-1-0 = mkCardano "release/1.0.x" nixpkgs-src.rev;
    cardano-sl-1-2 = mkCardano "release/1.2.0" nixpkgs-src.rev;
    daedalus = mkDaedalus "develop";
    iohk-nixops = mkNixops "master" nixpkgs-src.rev;
    iohk-nixops-staging = mkNixops "staging" nixpkgs-src.rev;
  });
  jobsetsAttrs =  daedalusPrJobsets // nixopsPrJobsets // (if handleCardanoPRs then cardanoPrJobsets else {}) // mainJobsets;
  jobsetJson = pkgs.writeText "spec.json" (builtins.toJSON jobsetsAttrs);
in {
  jobsets = with pkgs.lib; pkgs.runCommand "spec.json" {} ''
    cat <<EOF
    ${builtins.toJSON declInput}
    EOF
    cp ${jobsetJson} $out
  '';
}
