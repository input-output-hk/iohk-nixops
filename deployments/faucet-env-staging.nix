{ globals, ... }: with (import ./../lib.nix);
let nodeMap = { inherit (globals.fullMap) report-server; }; in


{
  faucet = { config, resources, ...}: {
    imports = [
      ./../modules/staging.nix
      ./../modules/datadog.nix
    ];
    services.faucet.faucet-config = {
      source-wallet-config = builtins.toString ./../static/wallet-source.json;
    };

  };
  resources.elasticIPs = nodesElasticIPs nodeMap;
}
