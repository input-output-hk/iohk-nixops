{ resources, config, pkgs, lib, nodes, ... }:

with lib;

let
  iohk-pkgs = import ../default.nix {};
  commonBuildMachineOpt = {
    speedFactor = 1;
    sshKey = "/etc/nix/id_buildfarm";
    sshUser = "root";
    system = "x86_64-linux";
    supportedFeatures = [ "kvm" "nixos-test" ];
  };
  mkLinux = hostName: commonBuildMachineOpt // {
    inherit hostName;
    maxJobs = 4;
  };
  mkMac = hostName: commonBuildMachineOpt // {
    inherit hostName;
    maxJobs = 2;
    system = "x86_64-darwin";
    sshUser = "builder";
    supportedFeatures = [];
  };
  hydraOverlay = self: super: {
    hydra = super.hydra.overrideDerivation (drv: {
      patches = [
        ./chomp.patch
        ./hydra-nix-prefetch-git.patch
        ./hydra-not-found.patch
      ];
    });
  };
  cleanIp = host: let
      ip1 = if nodes.${host}.options.networking.publicIPv4.isDefined then nodes.${host}.config.networking.publicIPv4 else "0.0.0.0";
    in
      if ip1 == null then "0.0.0.0" else ip1;
in {
  environment.etc = lib.singleton {
    target = "nix/id_buildfarm";
    source = ../static/id_buildfarm;
    uid = config.ids.uids.hydra;
    gid = config.ids.gids.hydra;
    mode = "0440";
  };

  environment.systemPackages = [ iohk-pkgs.iohk-ops ];

  nix = {
    distributedBuilds = true;
    buildMachines = [
      (mkLinux (cleanIp "hydra-build-slave-1"))
      (mkLinux (cleanIp "hydra-build-slave-2"))
      (mkMac "osx-1.aws.iohkdev.io")
      (mkMac "osx-2.aws.iohkdev.io")
      (mkMac "osx-3.aws.iohkdev.io")
    ];
    extraOptions = ''
      auto-optimise-store = true
      allowed-uris = https://github.com/NixOS/nixpkgs/archive
    '';
    binaryCaches = mkForce [ "https://cache.nixos.org" ];
  };

  # let's auto-accept fingerprints on first connection
  programs.ssh.extraConfig = ''
    StrictHostKeyChecking no
  '';

  services.hydra = {
    enable = true;
    hydraURL = "https://hydra.iohk.io";
    port = 8080;
    useSubstitutes = true;
    notificationSender = "hi@iohk.io";
    # max output is 4GB because of amis
    # auth token needs `repo:status`
    extraConfig = ''
      max_output_size = 4294967296
      store-uri = file:///nix/store?secret-key=/etc/nix/hydra.iohk.io-1/secret
      binary_cache_secret_key_file = /etc/nix/hydra.iohk.io-1/secret
      <github_authorization>
        input-output-hk = ${builtins.readFile ../static/github_token}
      </github_authorization>
      <githubstatus>
        jobs = serokell:iohk-nixops.*
        inputs = jobsets
        excludeBuildFromContext = 1
      </githubstatus>
      <githubstatus>
        jobs = serokell:cardano.*
        inputs = cardano
        excludeBuildFromContext = 1
      </githubstatus>
      <githubstatus>
        jobs = serokell:daedalus-.*:tests\..*
        inputs = daedalus
        excludeBuildFromContext = 1
      </githubstatus>
    '';
    logo = (pkgs.fetchurl {
      url    = "https://iohk.io/images/iohk-share-logo.jpg";
      sha256 = "0pg2igski35wf1y4gn8dxw6444kx1107mg4ns5xj29ays2c1j5sl";
    });
  };
  nixpkgs.overlays = [ hydraOverlay ];

  services.postgresql = {
    package = pkgs.postgresql96;
    dataDir = "/var/db/postgresql-${config.services.postgresql.package.psqlSchema}";
  };

  systemd.services.hydra-evaluator.path = [ pkgs.gawk ];
  systemd.services.hydra-manual-setup = {
    description = "Create Keys for Hydra";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      path = config.systemd.services.hydra-init.environment.PATH;
    };
    wantedBy = [ "multi-user.target" ];
    requires = [ "hydra-init.service" ];
    after = [ "hydra-init.service" ];
    environment = builtins.removeAttrs config.systemd.services.hydra-init.environment ["PATH"];
    script = ''
      if [ ! -e ~hydra/.setup-is-complete ]; then
        # create signing keys
        /run/current-system/sw/bin/install -d -m 551 /etc/nix/hydra.iohk.io-1
        /run/current-system/sw/bin/nix-store --generate-binary-cache-key hydra.iohk.io-1 /etc/nix/hydra.iohk.io-1/secret /etc/nix/hydra.iohk.io-1/public
        /run/current-system/sw/bin/chown -R hydra:hydra /etc/nix/hydra.iohk.io-1
        /run/current-system/sw/bin/chmod 440 /etc/nix/hydra.iohk.io-1/secret
        /run/current-system/sw/bin/chmod 444 /etc/nix/hydra.iohk.io-1/public
        # done
        touch ~hydra/.setup-is-complete
      fi
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme.certs = {
    "hydra.iohk.io" = {
      email = "info@iohk.io";
      user = "nginx";
      group = "nginx";
      webroot = config.security.acme.directory + "/acme-challenge";
      postRun = "systemctl reload nginx.service";
    };
  };

  services.nginx = {
    enable = true;
    httpConfig = ''
      server_names_hash_bucket_size 64;

      keepalive_timeout   70;
      gzip            on;
      gzip_min_length 1000;
      gzip_proxied    expired no-cache no-store private auth;
      gzip_types      text/plain application/xml application/javascript application/x-javascript text/javascript text/xml text/css;

      server {
        server_name _;
        listen 80;
        listen [::]:80;
        location /.well-known/acme-challenge {
          root ${config.security.acme.certs."hydra.iohk.io".webroot};
        }
        location / {
          return 301 https://$host$request_uri;
        }
      }

      server {
        listen 443 ssl spdy;
        server_name hydra.iohk.io;

        ssl_certificate /var/lib/acme/hydra.iohk.io/fullchain.pem;
        ssl_certificate_key /var/lib/acme/hydra.iohk.io/key.pem;

        location / {
          proxy_pass http://127.0.0.1:8080;
          proxy_set_header Host $http_host;
          proxy_set_header REMOTE_ADDR $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
        }
      }
    '';
  };
}
