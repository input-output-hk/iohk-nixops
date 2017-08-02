{ ... }:

let
  explorer = import ./cardano-explorer-config.nix;
in
with (import ./../lib.nix);
{
  network.description = "Cardano Explorer";

  sl-explorer = {
    imports = [
      # A node with 1) index 40, 2) no region and 3) in outer tier:
      (import ./../modules/cardano-node-config.nix explorer.sl-explorer)
      ./../modules/cardano-explorer.nix
    ];
  };
}
