{ globals, ... }: with (import ../lib.nix);
let nodeMap = { inherit (globals.fullMap) faucet; }; in

{
  faucet = {
    imports = [ ../modules/cardano-base.nix ../modules/cardano-faucet.nix ];
    params = nodeMap.faucet;
  };
}
