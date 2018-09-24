{ globals, ... }: with import ../lib.nix;
let
  nodeMap = globals.nodeMap;
  mkNode = name: value: {
    imports = [ ../modules/cardano.nix ];
    params = value;
  };
in

(mapAttrs mkNode nodeMap) // {
  require = [ ./mainnet-noauto-restart.nix ./global.nix ];
}
