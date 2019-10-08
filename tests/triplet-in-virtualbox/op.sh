#!/bin/sh
# shellcheck disable=SC2039,SC2191,SC2034,SC2086,SC2154

## 1. packages managed by Niv: ../nix/sources.json

CLUSTER_NAME=cardano
DEFAULT_NODE_NAME=a-node

fail() {
        echo "ERROR: $1" >&2; exit 1
}

topdir="$(git rev-parse --show-toplevel)"

cardano_node_override=()
while test -n "$1"
do case "$1" in
           --cardano-node )          cardano_node_override=(-I cardano-node="$2"); shift;;
           --cardano-node-relative ) cardano_node_override=(-I cardano-node="${topdir}/../cardano-node");;
           --verbose | -v ) set -x; verbose="--verbose";;
           --help | "--"* ) usage; exit 1;;
           * ) break;;
   esac; shift; done

niv=${topdir}/nix/sources.nix
test -f "${niv}" || fail "Can't locate Niv sources."

nixpkgs_drv=$(nix-instantiate -E "(import ${niv}).nixpkgs.outPath" | xargs echo)
test -f "${nixpkgs_drv}" || fail "Can't instantiate Nixpkgs drv from Niv: ${niv}"

nixpkgs_out=$(nix-store --realise --max-jobs 4 --cores 0 ${nixpkgs_drv})
test -d "${nixpkgs_out}" || fail "Can't realise Nixpkgs from: ${nixpkgs_drv}"

nix_opts=(             --max-jobs 4
                       --cores 0
                       --show-trace
	               -I "nixpkgs=${nixpkgs_out}"
                       -I "niv=${niv}")
nixops_subopts=(       --deployment "${CLUSTER_NAME}"
                       "${nix_opts[@]}")
nixops_subopts_deploy=("${nixops_subopts[@]}"
                       "${cardano_node_override[@]}"
                       --max-concurrent-copy=50)

cmd="$1"; shift
case "${cmd}" in
        setup )
                if ${nixops} info  "${nixops_subopts[@]}" >/dev/null 2>&1
                then op=modify
                else op=create; fi
                nixops ${op}   "${nixops_subopts[@]}" ./network.nix;;
        deploy )
                nixops deploy  "${nixops_subopts_deploy[@]}";;
        destroy )
                nixops destroy "${nixops_subopts[@]}";;
        ssh )
                nixops ssh     "${nixops_subopts[@]}" ${DEFAULT_NODE_NAME};;
        * )
                fail "Unknown command: ${cmd}";;
esac
