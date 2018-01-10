update_NIX_PATH() {
  local scriptDir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
  export NIX_PATH="nixpkgs=$(nix-build "${scriptDir}/../fetch-nixpkgs.nix" -o nixpkgs)"
}
update_NIX_PATH
