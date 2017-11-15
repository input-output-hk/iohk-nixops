#!/usr/bin/env bash

set -xeu

# https://github.com/NixOS/nixops/issues/693
export BOTO_CONFIG=/dev/null

source ./scripts/set_nixpath.sh

IOHK_OPS=${1:-$(nix-build -A iohk-ops)/bin/iohk-ops}
CLEANUP_DEPLOYS=${2:-true}
CLEANUP_CONFIGS=${3:-true}
WITH_STAGING=${4:-true}
WITH_PRODUCTION=${5:-true}
WITH_DEVELOPMENT=${6:-true}
WITH_EXPLORER=${7:-true}
WITH_REPORT_SERVER=${8:-true}
WITH_INFRA=${9:-true}


# PREPARE
mkdir -p cardano-sl/explorer/frontend/dist

touch static/github_token
touch static/id_buildfarm
touch static/datadog-api.secret static/datadog-application.secret

test -f static/tarsnap-cardano-deployer.secret ||
        { echo "secret" > static/tarsnap-cardano-deployer.secret; }

mkdir -p keys
for i in $(seq 0 9)
do touch keys/key$i.sk
done


# 0. Check all scripts compile
nix-shell --run "./scripts/aws.hs --help"
${IOHK_OPS} --help

# 1. check all packages build
nix-instantiate jobsets/cardano.nix --show-trace

# 2. check all environments evaluate
CLEANUP_DEPLS=""
cleanup() {
        set +xe
        for depl in ${CLEANUP_DEPLS}
        do
                test -z "${CLEANUP_DEPLOYS}" ||
                        ${IOHK_OPS} --config ${depl}'.yaml' destroy delete >/dev/null 2>&1
                test -z "${CLEANUP_CONFIGS}" ||
                        rm -f                ${depl}'.yaml'
        done
}
trap cleanup EXIT

banner() {
        echo -e "--\n--\n--  $*\n--\n--\n"
}

GENERAL_OPTIONS="--verbose --deployer 0.0.0.0"
COMMON_OPTIONS="--topology topology-min.yaml"
CARDANO_COMPONENTS="Nodes ${WITH_EXPLORER:+Explorer} ${WITH_REPORT_SERVER:+ReportServer}"

if test -n "${WITH_STAGING}"; then
CLEANUP_DEPLS="${CLEANUP_DEPLS} test-stag"
${IOHK_OPS}               new  --config 'test-stag.yaml'   --environment staging    ${COMMON_OPTIONS} 'test-stag'    ${CARDANO_COMPONENTS}
${IOHK_OPS} ${GENERAL_OPTIONS} --config 'test-stag.yaml'   create deploy --dry-run
banner 'Staging env evaluated'
fi

if test -n "${WITH_PRODUCTION}"; then
CLEANUP_DEPLS="${CLEANUP_DEPLS} test-prod"
${IOHK_OPS}               new  --config 'test-prod.yaml'   --environment production ${COMMON_OPTIONS} 'test-prod'    ${CARDANO_COMPONENTS}
${IOHK_OPS} ${GENERAL_OPTIONS} --config 'test-prod.yaml'   create deploy --dry-run
banner 'Production env evaluated'
fi

if test -n "${WITH_DEVELOPMENT}"; then
CLEANUP_DEPLS="${CLEANUP_DEPLS} test-devo"
${IOHK_OPS}               new  --config 'test-devo.yaml'                            ${COMMON_OPTIONS} 'test-devo'    ${CARDANO_COMPONENTS}
${IOHK_OPS} ${GENERAL_OPTIONS} --config 'test-devo.yaml'   create deploy --dry-run
banner 'Development env evaluated'
fi

if test -n "${WITH_INFRA}"; then
CLEANUP_DEPLS="${CLEANUP_DEPLS} test-infra"
${IOHK_OPS}               new  --config 'test-infra.yaml'  --environment production ${COMMON_OPTIONS} 'test-infra'   Infra
${IOHK_OPS} ${GENERAL_OPTIONS} --config 'test-infra.yaml'  create deploy --dry-run
banner 'Infra evaluated'
fi

./scripts/find-all-revisions.sh
