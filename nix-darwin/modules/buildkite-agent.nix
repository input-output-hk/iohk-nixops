{ config, pkgs, ... }:

let
  keys = "/Users/admin/buildkite";

in {
  services.buildkite-agent = let
    # nixos-unstable channel as of 2018-04-30
    unstablePkgs = import (pkgs.fetchFromGitHub {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "af55a0c300224fe9debfc4a57d7ee789e00e649d";
      sha256 = "13kgv7gr9p7fb51pqxx9dr51qz7f8ghqy57afzww1zhgmh4ismrx";
    }) { inherit (pkgs) config system; };
  in {
    enable = true;
    package = unstablePkgs.buildkite-agent3;
    runtimePackages = with pkgs; [ bash nix git ];
    meta-data = "system=x86_64-darwin";
    tokenPath = "${keys}/buildkite_token";
    openssh.privateKeyPath = "${keys}/id_buildkite";
    openssh.publicKeyPath = "${keys}/id_buildkite.pub";
    hooks.pre-command = ''
      creds=${keys}/buildkite_aws_creds
      if [ -e $creds ]; then
        source $creds
      else
        (>&2 echo "$creds doesn't exist. The build is going to fail.")
      fi
    '';
    hooks.environment = ''
      export NIX_BUILD_SHELL="/run/current-system/sw/bin/bash"
      # /usr/bin and /usr/sbin are added For iconutil, security, pkgutil, etc.
      # Required for daedalus installer build,
      # or any build which expects to have apple tools.
      export PATH="/run/current-system/sw/bin:$PATH:/usr/bin:/usr/sbin"
    '';
    extraConfig = ''
      no-pty=true
      # debug=true
      # priority=9
    '';
  };

  # this is required to actually create the users -- i don't know why
  users.knownUsers = [ "buildkite-agent" ];
  users.knownGroups = [ "buildkite-agent" ];
  users.users.buildkite-agent = {
    uid = 532;
    gid = 532;
  };
  users.groups.buildkite-agent.gid = 532;

  # Fix up group membership and perms on secrets directory.
  # Ensure that buildkite-agent home directory exists with correct
  # permissions.
  system.activationScripts.postActivation.text = ''
    dseditgroup -o edit -a admin -t user buildkite-agent
    mkdir -p ${keys}
    chgrp -R buildkite-agent ${keys}
    chmod -R o-rx ${keys}

    mkdir -p ${config.users.users.buildkite-agent.home}
    chown buildkite-agent:admin ${config.users.users.buildkite-agent.home}
    chmod 770 ${config.users.users.buildkite-agent.home}
  '';
}
