#!/usr/bin/env nix-shell
#! nix-shell -p jq -i bash

function runInShell {
  nix-shell -j 4 -p cabal2nix nix-prefetch-scripts coreutils cabal-install stack --run "$*"
}

set -xe
set -v

# Get relative path to script directory
scriptDir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")

source ${scriptDir}/../scripts/set_nixpath.sh

# Generate stack2nix Nix package
runInShell cabal2nix \
  --no-check \
  --revision $(jq .rev <  ${scriptDir}/../stack2nix-src.json -r) \
  https://github.com/input-output-hk/stack2nix.git > $scriptDir/stack2nix.nix

# Build stack2nix Nix package
nix-build ${scriptDir}/.. -A stack2nix -o $scriptDir/stack2nix

# Generate explorer until it's merged with cardano-sl repo
runInShell cabal2nix \
  --no-check \
  --revision $(jq .rev < ${scriptDir}/../cardano-sl-explorer-src.json -r) \
  https://github.com/input-output-hk/cardano-sl-explorer.git > $scriptDir/cardano-sl-explorer.nix

# Generate cardano-sl package set
runInShell $scriptDir/stack2nix/bin/stack2nix \
  --serialise --verbose \
  --revision $(jq .rev < ${scriptDir}/../cardano-sl-src.json -r) \
  https://github.com/input-output-hk/cardano-sl.git > $scriptDir/default.nix.new
mv $scriptDir/default.nix.new $scriptDir/default.nix

