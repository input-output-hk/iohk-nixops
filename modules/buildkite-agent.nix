{ name, pkgs, ... }:

{
  imports = [
    ./../modules/hydra-slave.nix
  ];

  services.buildkite-agent = {
    enable = true;
    name   = name;
    openssh.privateKeyPath = "/run/keys/buildkite-ssh-private";
    openssh.publicKeyPath  = "/run/keys/buildkite-ssh-public";
    tokenPath              = "/run/keys/buildkite-token";
    meta-data              = "system=x86_64-linux";
    hooksPath              = "/var/lib/buildkite-agent/hooks";
    runtimePackages        = with pkgs; [ gnutar gzip bzip2 xz ];
  };
  users.users.buildkite-agent.extraGroups = [ "keys" ];

  deployment.keys = {
    pre-command = {
      keyFile = ./. + "/../static/buildkite-hook";
      destDir = "/var/lib/buildkite-agent/hooks";
      user    = "buildkite-agent";
      permissions = "0770";
    };
    buildkite-ssh-private = {
      keyFile = ./. + "/../static/buildkite-ssh";
      user    = "buildkite-agent";
    };
    buildkite-ssh-public = {
      keyFile = ./. + "/../static/buildkite-ssh.pub";
      user    = "buildkite-agent";
    };
    buildkite-token = {
      keyFile = ./. + "/../static/buildkite-token";
      user    = "buildkite-agent";
    };
  };
}
