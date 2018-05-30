{ globals, ... }: with (import ./../lib.nix);

let params = globals.fullMap.faucet;
in
{
  faucet = { config, resources, ...}: {
    imports = [
      ./../modules/development.nix
    ];
    services.faucet.faucet-config = {
      source-wallet-config = builtins.toString ./../static/wallet-source.json;
    };

  };
}
