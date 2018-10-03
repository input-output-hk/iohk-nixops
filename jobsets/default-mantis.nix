{ nixpkgs ? <nixpkgs>
, declInput ? {
    uri = "git@github.com:input-output-hk/mantis-iele-ops.git";
    rev = "refs/heads/master";
  }
, mantisPrsJSON ? ./simple-pr-dummy.json
, solidityServicePrsJSON ? ./simple-pr-dummy.json
}:
let pkgs = import nixpkgs {};

    mantisPrs = builtins.fromJSON (builtins.readFile mantisPrsJSON );
    solidityServicePrs = builtins.fromJSON (builtins.readFile solidityServicePrsJSON );

    mkGitSrc = { repo, branch ? "refs/heads/master", deepClone ? false }: {
      type = "git";
      value = repo + " " + branch + (if deepClone then " deepClone" else "");
      emailresponsible = false;
    };

    mkJob = { name, description, nixexprinput ? "jobsetSrc", nixexprpath, extraInputs }: {
      inherit name;
      value = {
        inherit description nixexprinput nixexprpath;

        inputs = {
          jobsetSrc = mkGitSrc {
            repo = declInput.uri;
            branch = declInput.rev;
          };

          nixpkgs = mkGitSrc {
            repo = "https://github.com/NixOS/nixpkgs-channels";
            branch = "refs/heads/nixos-18.03";
          };
        } // extraInputs;

        enabled = 1;
        hidden = false;
        checkinterval = 90;
        schedulingshares = 100;
        emailoverride = "";
        enableemail = false;
        keepnr = 3;
      };
    };

    mkMantisJob = {
      name,
      description,
      mantisBranch ? "refs/heads/phase/iele_testnet",
      solidityServiceBranch ? "refs/heads/master"
    }:
      mkJob {
        inherit name description;
        nixexprpath = "jobsets/release-mantis.nix";
        extraInputs = {
          sbtVerifySrc = mkGitSrc {
            repo = "https://github.com/input-output-hk/sbt-verify.git";
            branch = "refs/tags/v0.4.1";
          };
          mantisSrc = mkGitSrc {
            repo = "git@github.com:input-output-hk/mantis-cardano.git";
            branch = mantisBranch;
            deepClone = true;
          };
          kevmSrc = mkGitSrc {
            repo = "https://github.com/kframework/evm-semantics.git";
            branch = "cc9c659510383215e5333d7f60088a2fdf2d120d";
          };
          secp256k1Src = mkGitSrc {
            repo = "https://github.com/bitcoin-core/secp256k1";
          };
          ieleSrc = mkGitSrc {
            repo = "https://github.com/runtimeverification/iele-semantics.git";
            branch = "f494469ddeceb356dc9ef2b654e136c38c14722b";
          };
          soliditySrc = mkGitSrc {
            repo = "https://github.com/runtimeverification/solidity.git";
            branch = "refs/heads/sol2iele";
          };
          solidityServiceSrc = mkGitSrc {
            repo = "https://github.com/input-output-hk/solidity-service.git";
            branch = solidityServiceBranch;
            deepClone = true;
          };
          solcBinSrc = mkGitSrc {
            repo = "https://github.com/ethereum/solc-bin.git";
            branch = "refs/heads/gh-pages";
          };
          remixIdeSrc = mkGitSrc {
            repo = "https://github.com/input-output-hk/remix-ide.git";
            branch = "refs/heads/phase/iele_testnet";
          };
        };
      };

    mantisJobsetDefinition = pkgs.lib.listToAttrs (
      [
        (mkMantisJob {
          name = "iele_testnet";
          description = "IELE Testnet";
        })
      ]
      ++
      (pkgs.lib.mapAttrsToList
        (
          num:
          info: mkMantisJob {
            name = "mantis-PR-${num}";
            description = info.title;
            mantisBranch = "pull/${num}/head";
          }
        )
        (pkgs.lib.filterAttrs (num: info: info.base.ref == "phase/iele_testnet") mantisPrs)
      )
      ++
      (pkgs.lib.mapAttrsToList
        (
          num:
          info: mkMantisJob {
            name = "solidity-service-PR-${num}";
            description = info.title;
            solidityServiceBranch = "pull/${num}/head";
          }
        )
        solidityServicePrs
      )
    );

    jobsetDefinition = mantisJobsetDefinition;
in {
  jobsets = pkgs.runCommand "spec.json" {} ''
    cat <<EOF
    ${builtins.toXML declInput}
    EOF

    tee $out <<EOF
    ${builtins.toJSON jobsetDefinition}
    EOF
  '';
}
