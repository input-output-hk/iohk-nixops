{ resources, config, pkgs, lib, nodes, ... }:

with lib;

let
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
  cleanIp = host: let
      ip1 = if nodes.${host}.options.networking.publicIPv4.isDefined then nodes.${host}.config.networking.publicIPv4 else "0.0.0.0";
    in
      if ip1 == null then "0.0.0.0" else ip1;
in {
  imports = [ ./github-webhook-util.nix ];
  environment.etc = lib.singleton {
    target = "nix/id_buildfarm";
    source = ../static/id_buildfarm;
    uid = config.ids.uids.hydra;
    gid = config.ids.gids.hydra;
    mode = "0440";
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      (mkLinux "builder-packet-c1-small-x86.aws.iohkdev.io")
      (mkLinux "builder-packet-c1-small-x86-2.aws.iohkdev.io")
      (mkLinux "builder-packet-c1-small-x86-3.aws.iohkdev.io")
      (mkLinux "builder-packet-c1-small-x86-4.aws.iohkdev.io")
      (mkLinux "builder-packet-c1-small-x86-5.aws.iohkdev.io")
      (mkMac "osx-1.aws.iohkdev.io")
      (mkMac "osx-2.aws.iohkdev.io")
      (mkMac "osx-3.aws.iohkdev.io")
      (mkMac "osx-4.aws.iohkdev.io")
      (mkMac "osx-5.aws.iohkdev.io")
    ];
    binaryCaches = mkForce [ "https://cache.nixos.org" ];
  };

  services.hydra = {
    hydraURL = "https://hydra.iohk.io";
    package = pkgs.callPackage ./hydra-fork.nix { nixpkgsPath = pkgs.path;
      src = pkgs.fetchFromGitHub {
        owner = "input-output-hk";
        repo = "hydra";
        rev = "5f30a105edeecf7c3408e56832a859e4385f06cb";
        sha256 = "102b085wmcnwl1qk077js8rv77f5y6jr0rnc3m6r25662h4lz7l4";
      };
    };
    # max output is 4GB because of amis
    # auth token needs `repo:status`
    extraConfig = ''
      max_output_size = 4294967296
      evaluator_max_heap_size = ${toString (5 * 1024 * 1024 * 1024)}

      max_concurrent_evals = 8

      store_uri = s3://iohk-nix-cache?secret-key=/etc/nix/hydra.iohk.io-1/secret&log-compression=br&region=eu-central-1
      server_store_uri = https://iohk-nix-cache.s3-eu-central-1.amazonaws.com/
      binary_cache_public_uri = https://iohk-nix-cache.s3-eu-central-1.amazonaws.com/
      log_prefix = https://iohk-nix-cache.s3-eu-central-1.amazonaws.com/
      upload_logs_to_binary_cache = true

      <github_authorization>
        input-output-hk = ${builtins.readFile ../static/github_token}
      </github_authorization>
      <githubstatus>
        jobs = Cardano:iohk-ops.*:required
        inputs = jobsets
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:iohk-nix.*:required
        inputs = iohk-nix
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:cardano.*:required
        inputs = cardano
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      # DEVOPS-1208 This CI status for cardano-sl is needed while the
      # Daedalus Windows installer is built on AppVeyor or Buildkite
      <githubstatus>
        jobs = Cardano:cardano-sl.*:daedalus-mingw32-pkg
        inputs = cardano
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:daedalus.*:tests\..*
        inputs = daedalus
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:plutus.*:required
        inputs = plutus
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:log-classifier.*:required
        inputs = log-classifier
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:ouroboros-network.*:required
        inputs = ouroboros-network
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:iohk-monitoring.*:required
        inputs = iohk-monitoring
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
      <githubstatus>
        jobs = Cardano:haskell-nix.*:required
        inputs = haskell-nix
        excludeBuildFromContext = 1
        useShortContext = 1
      </githubstatus>
    '';
  };
  deployment.keys."github-webhook-util".text = builtins.readFile ../static/github-webhook-util.secret;
  systemd.services."github-webhook-util" = {
    after = [ "github-webhook-util-key.service" ];
    wants = [ "github-webhook-util-key.service" ];
  };

  services.github-webhook-util = {
    enable = true;
    domain = "hydra.iohk.io";
    secrets = "/run/keys/github-webhook-util";
  };
  services.grafana = {
    enable = true;
    users.allowSignUp = true;
    domain = "hydra.iohk.io";
    rootUrl = "%(protocol)ss://%(domain)s/grafana/";
    extraOptions = {
      AUTH_GOOGLE_ENABLED = "true";
      AUTH_GOOGLE_CLIENT_ID = "778964826061-5v0m922g1qcbc1mdtpaf8ffevlso2v7p.apps.googleusercontent.com";
      AUTH_GOOGLE_CLIENT_SECRET = builtins.readFile ../static/google_oauth_hydra_grafana.secret;
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    virtualHosts = {
      "hydra.iohk.io" = {
        forceSSL = true;
        enableACME = true;
        locations."/".extraConfig = ''
          proxy_pass http://127.0.0.1:8080;
          proxy_set_header Host $http_host;
          proxy_set_header REMOTE_ADDR $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
        '';
        locations."~ /(nix-cache-info|.*\\.narinfo|nar/*)".extraConfig = ''
          return 301 https://iohk-nix-cache.s3-eu-central-1.amazonaws.com$request_uri;
        '';
        locations."/graph/".extraConfig = ''
          proxy_pass http://127.0.0.1:8081;
        '';
        locations."/grafana/".extraConfig = ''
          proxy_pass http://localhost:3000/;
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
