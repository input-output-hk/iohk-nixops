{ config, lib, pkgs, ... }:

with lib;

let
  ## isPath :: String -> Bool
  isPath = x: !(isAttrs x || isList x || isFunction x || isString x || isInt x || isBool x || isNull x)
               || (isString x && builtins.substring 0 1 x == "/");

  cfg = config.services.io-buildkite-agent;
  accessToken = if isPath cfg.token then readFile cfg.token else cfg.token;
  configFile = pkgs.writeText "buildkite-agent.cfg"
    ''
      token="${accessToken}"
      name="${cfg.name}"
      meta-data="${cfg.meta-data}"
      hooks-path="${pkgs.buildkite-agent}/share/hooks"
      build-path="/var/lib/buildkite-agent/builds"
      bootstrap-script="${pkgs.buildkite-agent}/share/bootstrap.sh"
    '';
in

{
  options = {
    services.io-buildkite-agent = {
      enable = mkEnableOption "buildkite-agent";

      token = mkOption {
        type = types.either types.str types.path;
        description = ''
          The token from your Buildkite "Agents" page.

          Either a literal string value, or a path to the token file.
        '';
      };

      name = mkOption {
        type = types.str;
        description = ''
          The name of the agent.
        '';
      };

      meta-data = mkOption {
        type = types.str;
        default = "";
        description = ''
          Meta data for the agent.
        '';
      };

      openssh =
        { privateKey = mkOption {
            type = types.either types.str types.path;
            description = ''
              Private agent key.

              Either a literal string value, or a path to the token file.
            '';
          };
          publicKey = mkOption {
            type = types.either types.str types.path;
            description = ''
              Public agent key.

              Either a literal string value, or a path to the token file.
            '';
          };
        };
    };
  };

  config = mkIf config.services.io-buildkite-agent.enable {
    users.extraUsers.io-buildkite-agent =
      { name = "buildkite-agent";
        home = "/var/lib/buildkite-agent";
        createHome = true;
        description = "Buildkite agent user";
        extraGroups = [ "keys" ];
      };

    environment.systemPackages = [ pkgs.buildkite-agent ];

    systemd.services.io-buildkite-agent =
      let copyOrEcho       = x: target: perms:
                             (if isPath x
                              then "cp -f ${x} ${target}; "
                              else "echo '${x}' > ${target}; ")
                             + "${pkgs.coreutils}/bin/chmod ${toString perms} ${target}; ";
      in
      { description = "Buildkite Agent";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment.HOME = "/var/lib/buildkite-agent";
        preStart = ''
            ${pkgs.coreutils}/bin/mkdir -m 0700 -p /var/lib/buildkite-agent/.ssh
            ${copyOrEcho cfg.openssh.privateKey "/var/lib/buildkite-agent/.ssh/id_rsa"     600}
            ${copyOrEcho cfg.openssh.publicKey  "/var/lib/buildkite-agent/.ssh/id_rsa.pub" 600}
          '';

        serviceConfig =
          { ExecStart = "${pkgs.buildkite-agent}/bin/buildkite-agent start --config ${configFile}";
            User = "buildkite-agent";
            RestartSec = 5;
            Restart = "on-failure";
            TimeoutSec = 10;
          };
      };
  };
}
