HASH_COMMIT=$1

ssh staging@35.156.156.28
cd ~/devops-86-deploy-staging-explorer/pkgs
# MAC users, beware! Not sure if the flags are correct.
sed -ri "s/cabal2nix https:\/\/github\.com\/input-output-hk\/cardano-sl-explorer\.git --no-check --revision(.*?)> cardano-sl-explorer.nix/cabal2nix https:\/\/github\.com\/input-output-hk\/cardano-sl-explorer\.git --no-check --revision $HASH_COMMIT > cardano-sl-explorer.nix/g" generate.sh
./generate.sh 
cd ~/devops-86-deploy-staging-explorer/cardano-sl-explorer/frontend
git stash
git fetch
git checkout $HASH_COMMIT
git stash pop
NIX_PATH=nixpkgs=https://github.com/NixOS/nixpkgs/archive/ebbababd8f9cb49d039f11d58e4e49d8e02d7533.tar.gz EXPLORER_NIX_FILE=./../default.nix ./scripts/build.sh
cd ~/devops-86-deploy-staging-explorer/
./CardanoCSL.hs deploy -c config.yaml