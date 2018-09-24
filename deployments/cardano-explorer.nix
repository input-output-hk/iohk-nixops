{ globals, ... }: with import ../lib.nix;
let nodeMap = { inherit (globals.fullMap) explorer; }; in

{
  explorer = {
    imports = [ ../modules/cardano-explorer.nix ];
    params = nodeMap.explorer;
  };
}
