{ config, pkgs, lib, ... }:

with (import ./../lib.nix);

let
  iohk-pkgs = import ../default.nix {};
in {
  imports = [ ./ntp_fix.nix ];
  boot.kernel.sysctl = {
    ## DEVOPS-592
    "kernel.unprivileged_bpf_disabled" = 1;
  };

  environment.systemPackages = with pkgs;
    # nixopsUnstable: wait for 1.5.1 release
    [ git tmux vim sysstat iohk-pkgs.nixops lsof ncdu tree mosh tig
      cabal2nix stack iptables graphviz tcpdump strace gdb binutils nix-repl ];

  services.openssh.passwordAuthentication = false;
  services.openssh.enable = true;
  # Non-root users are not allowed to install authorized keys.
  services.openssh.authorizedKeysFiles = pkgs.lib.mkForce
    [ "/etc/ssh/authorized_keys.d/%u" ];
  services.openssh.extraConfig = lib.mkOrder 999 ''
    Match User root
        AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/authorized_keys.d/%u
  '';

  services.ntp.enable = true;

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = devOpsKeys;

  environment.variables.TERM = "xterm-256color";

  systemd.coredump = {
    enable = hasAttr "cardano-node" config.services &&
        config.services.cardano-node.saveCoreDumps;
    extraConfig = "ExternalSizeMax=${toString (8 * 1024 * 1024 * 1024)}";
  };

  services.cron.enable = true;
  #services.cron.systemCronJobs = [
  #  "*/1 * * * *  root /run/current-system/sw/lib/sa/sadc -S DISK 2 29 /var/log/saALL"
  #];

  nix = rec {
    # use nix sandboxing for greater determinism
    useSandbox = true;

    # make sure we have enough build users
    nrBuildUsers = 30;

    # if our hydra is down, don't wait forever
    extraOptions = ''
      connect-timeout = 10
    '';

    # use all cores
    buildCores = 0;

    # allow 4 substituters in parallel
    maxJobs = 4;

    nixPath = [ "nixpkgs=/run/current-system/nixpkgs" ];

    # use our hydra builds
    trustedBinaryCaches = [ "https://cache.nixos.org" "https://hydra.iohk.io" ];
    binaryCaches = trustedBinaryCaches;
    binaryCachePublicKeys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };
  system.extraSystemBuilderCmds = ''
    ln -sv ${fetchNixPkgs} $out/nixpkgs
  '';

  # Mosh
  networking.firewall.allowedUDPPortRanges = [
    { from = 60000; to = 61000; }
  ];
}
