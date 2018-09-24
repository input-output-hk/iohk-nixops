{ globals, ... }:

{
  defaults = {
    global = {
      inherit (globals) environment systemStart topologyYaml nodeMap nRelays relays;
    };
  };
}
