## NOTE: this file should be kept in structural sync with 'srcroot://topology.yaml'
{ sl-explorer = rec {
                i = 40;
             name = "sl-explorer"; # This is an important identity, let's not break it.
           region = "eu-central-1";
             type = "explorer";
            peers = [];
           relays = [];
          sgNames = [ "allow-deployer-ssh-${region}"
                      "allow-to-explorer-${region}" ];
  };
}
