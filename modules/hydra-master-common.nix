{ resources, config, pkgs, lib, nodes, ... }:

with lib;

let
  iohk-pkgs = import ../default.nix {};
  hydraRev = "82b8997da6b5edc6cbdd5511aa1636a1c46ea50c";
  hydraSrc = pkgs.fetchFromGitHub {
    owner = "cleverca22";
    repo = "hydra";
    sha256 = "0wnhlq5vi6hkcizicflgcf75a5qw84a5950kkvay0an2g7zb8n42";
    rev = hydraRev;
  };
  hydraSrc' = {
    outPath = hydraSrc;
    rev = builtins.substring 0 6 hydraRev;
    revCount = 1234;
  };
  hydra-fork = (import (hydraSrc + "/release.nix") { nixpkgs = pkgs.path; hydraSrc = hydraSrc'; }).build.x86_64-linux;
in {
  nix = {
    extraOptions = ''
      auto-optimise-store = true
      allowed-uris = https://github.com/NixOS/nixpkgs/archive https://github.com/input-output-hk/nixpkgs/archive
    '';
    binaryCaches = mkForce [ "https://cache.nixos.org" ];
  };

  # let's auto-accept fingerprints on first connection
  programs.ssh.extraConfig = ''
    StrictHostKeyChecking no
  '';

  services.hydra = {
    enable = true;
    port = 8080;
    package = hydra-fork;
    useSubstitutes = true;
    notificationSender = "hi@iohk.io";
    logo = (pkgs.fetchurl {
      url    = "https://iohk.io/images/iohk-share-logo.jpg";
      sha256 = "0pg2igski35wf1y4gn8dxw6444kx1107mg4ns5xj29ays2c1j5sl";
    });
  };

  services.postgresql = {
    package = pkgs.postgresql96;
    dataDir = "/var/db/postgresql-${config.services.postgresql.package.psqlSchema}";
  };

  systemd.services.hydra-evaluator.path = [ pkgs.gawk ];
  systemd.services.hydra-queue-runner.serviceConfig = {
    ExecStart = mkForce "@${config.services.hydra.package}/bin/hydra-queue-runner hydra-queue-runner -v";
  };
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

  services.nginx.enable = true;
}
