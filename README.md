Collection of tools to deploy IOHK infrastructure.

### File structure

- `deployments` - includes all NixOps deployments inputs controlled via `.hs` scripts
- `modules` - NixOS modules
- `lib.nix` - wraps upstream `<nixpkgs/lib.nix>` with our common functions
- `scripts` - has bash scripts not converted to Haskell/Turtle into Cardano.hs yet
- `default.nix` - is a collection of Haskell packages
- `static` includes files using in deployments
- `jobsets` jobsets declaratively provisioned by Hydra CI
- `tests` - NixOS tests for the `modules`
- `iohk` - Haskell automation of opsy stuff


### Usage

    $(nix-build -A iohk-ops)/bin/iohk-ops --help


### Deployments file structure

There is one global resource file `deployments/keypairs.nix` for all deployments. That's where
resources that are only needed in all of deployments are provisioned.

Per each set of machines (which can be combined or used standalone in a deployment) there are files:

- `{purpose}.nix` set of "logical" machines
- `{purpose}-target-{target}.nix` set of physical machines for given target (aws, ...)
- `{purpose}-env-{environment}.nix` set of environment specific overrides (currently implies aws target)

[Explanation about logical vs physical can be found in Nixops manual](https://nixos.org/nixops/manual/#chap-introduction)

Example for deploying cardano nodes in production:

- cardano-nodes.nix
- cardano-nodes-target-aws.nix
- cardano-nodes-env-production.nix


### Getting SSH access

Append https://github.com/input-output-hk/pos-prototype-deployment/blob/master/lib.nix#L46 and submit a PR.
