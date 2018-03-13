{ config, pkgs, ... }:

let
  keys = "/Users/admin/buildkite";

in {
  services.buildkite-agent = let
    # something off the nixos-unstable branch
    unstablePkgs = import (pkgs.fetchFromGitHub {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "8b1cf100cd8badad6e1b6d4650b904b88aa870db";
      sha256 = "1p0xxyz30bd2bg0wrfviqgsskz00w647h0l2vi33w90i42k8r3li";
    }) { inherit config; };
  in {
    enable = true;
    package = unstablePkgs.buildkite-agent;
    runtimePackages = with pkgs; [ bash nix git ];
    meta-data = "system=x86_64-darwin";
    tokenPath = "${keys}/buildkite_token";
    openssh.privateKeyPath = "${keys}/id_buildkite";
    openssh.publicKeyPath = "${keys}/id_buildkite.pub";
    hooks.pre-command = ''
      creds=${keys}/buildkite_aws_creds
      if [ -e \$creds ]; then
        source \$creds
      else
        (>&2 echo "\$creds doesn't exist. The build is going to fail.")
      fi
    '';
    # Protip: escape all $ not intended for expansion by nix
    hooks.environment = ''
      # For iconutil, security, pkgutil, etc.
      # Required for daedalus installer build,
      # or any build which expects to have apple tools.
      export PATH=\$PATH:/usr/bin:/usr/sbin
    '';
    extraConfig = ''
      git-clean-flags=-fdxq
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
}
