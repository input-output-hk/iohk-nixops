#!/usr/bin/env bash

# ran to propose an update to the cluster

source config

./auxx/bin/cardano-auxx $COMMONOPTS $AUXXOPTS cmd --commands "propose-update ${VOTER_INDEX} vote-all ${lastKnownBlockVersion} 65536 70000 csl-daedalus:${applicationVersion} win64 ${WIN64_INSTALLER} none macos64 ${DARWIN_INSTALLER} none"

echo you must now update the config file to contain the proposal ID
