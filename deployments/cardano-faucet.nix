{ globals, ... }:

{
  faucet = import ./../modules/cardano-faucet.nix globals.fullMap.faucet;
}
