{ nixopsPrsJSON ? ./simple-pr-dummy.json
, cardanoPrsJSON ? ./simple-pr-dummy.json
, nixpkgs ? <nixpkgs>
, declInput ? {}
}:

# Followed by https://github.com/NixOS/hydra/pull/418/files

let
  nixopsPrs = builtins.fromJSON (builtins.readFile nixopsPrsJSON);
  cardanoPrs = builtins.fromJSON (builtins.readFile cardanoPrsJSON);
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
        jobsets = mkFetchGithub "https://github.com/${info.head.repo.owner.login}/${info.head.repo.name}.git ${info.head.ref}";
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
        cardano = mkFetchGithub "https://github.com/${info.head.repo.owner.login}/${info.head.repo.name}.git ${info.head.ref}";
      };
    };
  };
  nixopsPrJobsets = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeNixopsPR nixopsPrs);
  cardanoPrJobsets = pkgs.lib.listToAttrs (pkgs.lib.mapAttrsToList makeCardanoPR cardanoPrs);
  mainJobsets = with pkgs.lib; mapAttrs (name: settings: defaultSettings // settings) (rec {
    cardano-sl = mkCardano "master" nixpkgs-src.rev;
    cardano-sl-1-0 = mkCardano "cardano-sl-1.0" nixpkgs-src.rev;
    iohk-nixops = mkNixops "master" nixpkgs-src.rev;
    iohk-nixops-staging = mkNixops "staging" nixpkgs-src.rev;
  });
  jobsetsAttrs =  nixopsPrJobsets // cardanoPrJobsets // mainJobsets;
  jobsetJson = pkgs.writeText "spec.json" (builtins.toJSON jobsetsAttrs);
in {
  jobsets = with pkgs.lib; pkgs.runCommand "spec.json" {} ''
    cat <<EOF
    ${builtins.toJSON declInput}
    EOF
    cp ${jobsetJson} $out
  '';
}
