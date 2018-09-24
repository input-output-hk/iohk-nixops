# Intro

This document describes the IOHK ops tool (`iohk-ops`).

`iohk-ops` is primarily a convenient wrapper for NixOps, but it also
performs other ops tasks.

The script entry point is [`iohk/iohk-ops.hs`](https://github.com/input-output-hk/iohk-ops/blob/master/iohk/iohk-ops.hs)
and all of the sources are in the [iohk-ops](https://github.com/input-output-hk/iohk-ops)
repo.

It can be invoked with:

 - `$(nix-build -A iohk-ops)/bin/iohk-ops --help`

 - `nix-shell` then `io --help` (io is a shell function)

 - `io --help` (from `staging@cardano-deployer`)

For an example deployment scenario, see [Example Deployment](#example-deployment)

# Subcommands
## General

- `template [--node-limit N] [--environment ENV] [--target TGT] BRANCH DEPLOYMENT...`: produce (or update) a checkout of BRANCH with a configuration YAML file (whose name depends on the _environment_), primed for future operations.
    - `--node-limit` allows patch-less limiting of the cluster size;  A suitable value is `4` _: -)_
- `set-cardano COMMIT`, `set-explorer COMMIT`: set the `cardano-sl-src.json` and `cardano-sl-explorer-src.json` with inputs, suitable to parametrise various ops, for instance `pkgs/generate.sh`
- `mini-keys`: fake/request/provide a minimum set of keys required for a minimum complete deployment (_explorer_ + _report-server_ + _nodes_ -- henceforth referred to as MCD)
- `do`: chain commands, like:

```
io -c staging.yaml do destroy delete create deploy   ## ..same as fromscratch
```

## Build

- `genesis`: initiate production of _Genesis_ in `cardano-sl/genesis` subdir
    - NOTE: _this depends on merging of https://github.com/input-output-hk/cardano-sl/pull/1027_
- `build`, `ami`: _to-be-documented_, _well-known_

## Cluster lifecycle

- `create`, `modify`, `deploy`, `destroy`, `delete`, `info`: use the corresponding `<config>.yaml` to drive a corresponding `nixops` command
- `fromscratch`: established synonym for `do destroy delete create deploy`

## Live cluster ops
### `cardano-sl`
- `checkstatus`, `start`, `stop`: _to-be-documented_, _well-known_
- `firewall-block-region`, `firewall-clear`: _to-be-documented_, _well-known_
- `runexperiment`, `postexperiment`: _to-be-documented_, _well-known_
- `dumplogs`, `date`: _to-be-documented_, _well-known_

# Example deployment

First, let's assume the following:

- it's a _development_ environment cluster
- we want to limit cluster size to 4 nodes
- we want the full package: _nodes_, _cardano-explorer_ and _report-server_

This translates to:
```
$ io template --environment development --node-limit 4 some-branch Nodes Explorer ReportServer
...observe git clone
...observe the generated config.yaml
$ cd some-branch
$ io -c staging.yaml do create mini-keys deploy
_..enter DataDog keys -- if on staging/production -- otherwise feel free to enter anything here.._
...
some-branch> deployment finished successfully
```

## Build network locally, but don't deploy

For testing purposes, it may be useful to see how the NixOps machines
would look like without actually deploying anything. Use the command:

    io --deployer 127.0.0.1 --config mainnet.yaml deploy --build-only

 * `--build-only` is the option which prevents actual deployment.
 * Setting `--deployer` is required when not running within AWS.

### Dummy secrets files

You need to ensure the following files are present (they can just be empty):

- `keys/key1.sk`
- `static/datadog-api.secret`
- `static/datadog-application.secret`
- `static/id_buildfarm`
- `static/github_token`

### Lack of memory

If you don't have enough memory to build, then set the `iohk-ops --initial-heap-size` option (value is in gibibytes), and trim
[`topology-production.yaml`](https://github.com/input-output-hk/iohk-ops/blob/master/topology-production.yaml).

To trim the topology file:
1. Delete all entries except `c-a-1`, `r-a-1`, `p-b-1`. That will
   leave just one core node, one relay node, and one public relay
   node.
2. In the `static-routes` attributes, delete all list elements for
   routes to nodes which no longer exist.


# Installer commands

The following subcommands have been rolled into a single
`update-proposal` subcommand:

 - `find-installers`
 - `s3upload`
 - `set-version-json`
 
See [Daedalus Installer Update Procedure](./Daedalus-Installer-Update-Procedure.md)
for instructions.

## find-installers

The script to check CI for installers of a particular revision can be
run stand-alone. It won't download anything, unless a destination
directory is given.

    io -c mainnet.yaml find-installers -r REV [--download DIRECTORY]

Example output:

    ============================================================
    Daedalus version:   0.10.0
    Daedalus rev:       07b63de0c6177e60f4715f89bb75793608a47fdd

    Cardano SL version: 1.1.1
    Cardano SL rev:     af2894a2770112391ea96bc9af6718451fa26539

    applicationVersion: 6


    CI links:
    * https://buildkite.com/input-output-hk/daedalus/builds/1252
    * https://ci.appveyor.com/project/input-output/daedalus/build/1.2.0.6339

    Mainnet installers:
    macOS - https://ci-output-sink.s3.amazonaws.com/csl-daedalus/daedalus-0.10.0-cardano-sl-1.2.0.1252-mainnet-macos.pkg
    Windows - https://ci.appveyor.com/api/buildjobs/kdx370l6and39iou/artifacts/installers/daedalus-0.10.0-cardano-sl-1.2.0.6339.0-mainnet-windows.exe

    Staging installers:
    macOS - https://ci-output-sink.s3.amazonaws.com/csl-daedalus/daedalus-0.10.0-cardano-sl-1.2.0.1252-staging-macos.pkg
    Windows - https://ci.appveyor.com/api/buildjobs/kdx370l6and39iou/artifacts/installers/daedalus-0.10.0-cardano-sl-1.2.0.6339.0-staging-windows.exe

    ============================================================


# Configuration

## GitHub API Token `./github_token`

Note that GitHub limits unauthenticated users to 60 API calls per hour. Under normal use of `iohk-ops`, it's unlikely that this limit will ever be reached, but when testing heavily, or if your IP has already consumed the entire API quota, it may be necessary to configure an API token.

If you create a `github_token` file in the current directory containing the string `token <sha1>` then it will perform authenticated requests.

You get the SHA1 from <https://github.com/settings/tokens>.

## Buildkite API Token `static/buildkite_token`

The installer upload script requires access to Buildkite. Visit <https://buildkite.com/user/api-access-tokens> and create an access token with at least `read_builds` scope. Put this into `static/buildkite_token`.
