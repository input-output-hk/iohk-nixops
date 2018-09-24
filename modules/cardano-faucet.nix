with (import ./../lib.nix);

{ config, pkgs, lib, ...}:

let
  recaptcha = {
    siteKey = lib.fileContents ../static/recaptcha_site_key;
    secretKeyFile = "/var/lib/keys/recaptcha-secret-key";
  };
  iohkPkgs = import ../default.nix { inherit config pkgs; inherit (pkgs) system; };

  faucetFrontend = iohkPkgs.makeFaucetFrontend {
    explorerURL = "http://cardano-explorer.cardano-testnet.iohkdev.io/";
    recaptchaSiteKey = recaptcha.siteKey;
  };

  explorerURL = "http://cardano-explorer.cardano-testnet.iohkdev.io/";

in {
  global.dnsHostname = mkForce "cardano-faucet";

  imports = [ ./cardano-faucet-module.nix ];

  services.cardano-faucet = {
    enable = true;
    relayHost = "relays.cardano-testnet.iohkdev.io";
    configKey = "testnet_full";
    statsd.enable = true;
    statsd.port = 8125; # dogstatsd will be listening on this port
    inherit recaptcha;
  };

  deployment.keys.recaptcha-secret-key = {
    keyFile = ../static/recaptcha_secret_key;
    destDir = "/var/lib/keys";
    user = "cardano-faucet";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = {
    enable = true;
    virtualHosts = let
      vhostDomainName = if config.global.dnsDomainname != null
        then config.global.dnsDomainname else "iohkdev.io";
      # allowOrigin = "https://testnet.iohkdev.io";
      allowOrigin = "*"; # need to include https://webdevc.iohk.io for the time being
     in {
      "cardano-faucet.${vhostDomainName}" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            extraConfig = ''
              if ($request_method = 'OPTIONS') {
                 add_header 'Access-Control-Allow-Origin' '${allowOrigin}' always;
                 add_header 'Vary' 'Origin' always;
                 add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
                 #
                 # Custom headers and headers various browsers *should* be OK with but aren't
                 #
                 add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
                 #
                 # Tell client that this pre-flight info is valid for 20 days
                 #
                 add_header 'Access-Control-Max-Age' 1728000;
                 add_header 'Content-Type' 'text/plain; charset=utf-8';
                 add_header 'Content-Length' 0;
                 return 204;
              }

              root ${faucetFrontend};
              try_files $uri $uri/index.html @faucet;
            '';
          };
          "@faucet" = {
            proxyPass = "http://127.0.0.1:${toString config.services.cardano-faucet.port}";
          };
        };
        
        extraConfig = ''
          # Otherwise nginx serves files with timestamps unixtime+1 from /nix/store
          if_modified_since off;
          add_header Last-Modified "";
          etag off;

          # CORS support
          add_header 'Access-Control-Allow-Origin' '${allowOrigin}' always;
          add_header 'Vary' 'Origin' always;
          add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
          add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
          add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        '';
      };
    };
  };
}
