# Developer Clusters HOWTO

This document describes how to launch a Cardano cluster on AWS from scratch.

## Intended audience

This document is to support developers in their need to deploy ad hoc clusters.

## Requirements

1. [SSH access to the `staging` deployer](https://github.com/input-output-hk/iohk-ops#getting-ssh-access)

## Inputs

1. [cardano-sl](https://github.com/input-output-hk/cardano-sl) git revision hash.
1. [iohk-ops](https://github.com/input-output-hk/iohk-ops) branch.  In absence of preference, the default is `develop`.
1. [Issue ID](https://iohk.myjetbrains.com) being worked on.

## Steps

Note that `io` is an alias to `iohk-ops` which becomes available when
you enter the `nix-shell`.

Replace `ISSUE-ID` with your issue ID, or any name to identify the cluster.
This should all be _in lowercase_ to avoid problems when updating DNS entries.

1. SSH to the `staging` jumpserver.
1. `iohk-ops clone ISSUE-ID [IOHK-OPS-BRANCH]` -- the branch defaults to `master`.
1. `cd ISSUE-ID`
1. `iohk-ops set-rev cardanosl CARDANO-REVISION`
1. `nix-shell -A withAuxx`
1. `io new [--dont-generate-keys] [--configuration-key CONFIGURATION-KEY] ISSUE-ID Nodes [Explorer] [ReportServer]`
   - the `CONFIGURATION-KEY` defaults to `devnet`
   - this will generate stake keys using `cardano-keygen`, unless `--dont-generate-keys` was passed
   - the elements after `ISSUE-ID` name cluster components, for the CSL nodes, explorer and report server, correspondingly -- which all are, strictly speaking, optional, with the caveat that having a `Nodes`-free cluster doesn't make a lot of sense
1. `io deploy`, with following optional arguments:
   - `--bump-system-start-held-by 15` -- bump `--system-start` by N minutes _from *now*_, where _*now*_ is the moment when the `deploy` subcommand starts to execute (which might be later than the invocation of the `io` command itself, due to command pipelining)
1. Make sure to use `io destroy --confirm delete` after you are done with the cluster to destroy the _Nixops deployment_ -- all the local files remain intact.

## Obtaining journals

`systemd-journald` journals can be obtained -- either cluster-wide, or from a single node:

`iohk-ops [--on u-a-1] -c staging-testnet.yaml get-journals [--since "2017-11-18 21:10:00 UTC"] [--until "2017-11-18 21:40 UTC"]`

Notably:

- `--on NODE-NAME`
- `--since JOURNALD-TIME-SPEC`, defaults to `6 hours ago`
- `--until JOURNALD-TIME-SPEC`, defaults to unspecified (essentially `now`)

## Restarting cluster faster, without full machine redeployment

When one wants to redeploy a cluster, it's not necessary to destroy the machines and redeploy them from scratch: typically the following will suffice:

    io deploy --build-only     # only need this on deployments of new cardano commits
    io stop wipe-node-dbs --confirm wipe-journals deploy --bump-system-start-held-by 5

## Operating a cluster with directly-specified, non-generated genesis

1. The genesis JSON file must be referred to from the `configuration.yaml` for the `cardano-sl` commit specified in `cardano-sl-src.json`.
1. Secret keys need to be placed at `keys/keyN.sk`, where `N` ranges in `0..k-1`, where k is the number of nodes.
1. `io new` needs be passed `--dont-generate-keys`
1. `io deploy` needs _NOT_ be passed `--bump-system-start-held-by`

## Connect a wallet to the developer cluster

This uses the customizable wallet connect script generator in cardano-sl
(see [Exchange Onboarding](https://github.com/input-output-hk/cardano-sl/blob/develop/docs/exchange-onboarding.md#generate-custom-configuration)).

The `io set-rev` command will have already cloned cardano-sl, so
change to that directory. **Important**: make sure you are in the
`cardano-sl` directory not `iohk-ops` -- otherwise the parameters
won't take effect.

Create a file called `custom-wallet-config.nix` with the following
contents:

    {
      walletListen = "127.0.0.1:8090";

      ## Directory for the wallet's local state.
      ## must be enclosed in double quotes.
      stateDir = "./state-wallet-fragment";

      ## Set this to the DNS name of the relay in the dev cluster.
      relays = "r1-ISSUE-ID.aws.iohkdev.io";

      # Selects the "devnet" configuration,
      environment = "override";
      confFile = ./lib/configuration.yaml;
      confKey = "devnet";

       # A dummy value is required or the wallet will fail.
       additionalNodeArgs = "--system-start 1";
    }

That file contains the parameters for building the connect script. If
the parameters change, then the connect script needs to be built
again. To build the connect script:

    nix-build -A connectScripts.demoWallet -o ./connect-devnet.sh

Run the wallet and it will connect to the developer cluster.

    ./connect-devnet.sh
