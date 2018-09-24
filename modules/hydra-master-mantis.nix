{ resources, config, pkgs, lib, nodes, ... }:

with lib;

let
  hydraDnsName = "mantis-hydra.aws.iohkdev.io";
in {

  nix = {
    buildMachines = [
      { hostName = "localhost";
        system = "x86_64-linux,builtin";
        maxJobs = 8;
        supportedFeatures = ["kvm" "nixos-test"];
      }
    ];
    gc.automatic = true;
    useSandbox = mkForce false;
  };

  services.fail2ban.enable = true;
  virtualisation.docker.enable = true;

  services.hydra = {
    hydraURL = "https://${hydraDnsName}";
    # max output is 4GB because of amis
    # auth token needs `repo:status`
    extraConfig = ''
      max_output_size = 4294967296
      store-uri = file:///nix/store?secret-key=/etc/nix/${hydraDnsName}-1/secret
      binary_cache_secret_key_file = /etc/nix/${hydraDnsName}-1/secret
      <github_authorization>
        input-output-hk = ${builtins.readFile ../static/github_token}
      </github_authorization>
    '';
  };

  services.nginx = {
    virtualHosts = {
      "${hydraDnsName}" = {
        forceSSL = true;
        enableACME = true;
        locations."/".extraConfig = ''
          proxy_pass http://127.0.0.1:8080;
          proxy_set_header Host $http_host;
          proxy_set_header REMOTE_ADDR $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
        '';
      };
    };
    commonHttpConfig = ''
      server_names_hash_bucket_size 64;
      keepalive_timeout   70;
      gzip            on;
      gzip_min_length 1000;
      gzip_proxied    expired no-cache no-store private auth;
      gzip_types      text/plain application/xml application/javascript application/x-javascript text/javascript text/xml text/css;
    '';
  };
}
