{ python3, makeWrapper, runCommand }:

let
  python = python3.withPackages (ps: with ps; [ netifaces prometheus_client requests dateutil ]);
  inherit ((import ../../lib.nix).rust-packages.pkgs) jormungandr-cli;
in runCommand "jormungandr-monitor" {
  buildInputs = [ python makeWrapper ];
  jcli = "${jormungandr-cli}/bin/jcli";
} ''
  substituteAll ${ ./jormungandr-monitor.py } $out
  chmod +x $out
  patchShebangs $out
''
