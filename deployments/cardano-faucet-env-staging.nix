{ globals, ... }: with (import ../lib.nix);
let nodeMap = { inherit (globals.fullMap) faucet; }; in

{
  faucet = (import ../modules/cardano-staging.nix) nodeMap.faucet;
  monitoring = lib.optionalAttrs (nodeMap.faucet.nodeImpl == "haskell") {
    services.monitoring-services = {
      applicationRules = [
        {
          alert = "cardano_faucet_balance_monitor";
          expr = "faucet_wallet_balance < 10000000000";
          for = "1m";
          labels.severity = "page";
          annotations = {
            description = "{{$labels.alias}} Staging faucet wallet balance is low";
          };
        }
      ];
    };
  };
  resources = {
    elasticIPs = nodesElasticIPs nodeMap;
  };
}
