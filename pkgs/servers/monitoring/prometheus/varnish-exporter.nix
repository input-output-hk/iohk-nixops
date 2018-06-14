# This file was generated by go2nix.
{ stdenv, lib, buildGoPackage, fetchFromGitHub, makeWrapper, varnish }:

buildGoPackage rec {
  name = "prometheus_varnish_exporter-${version}";
  version = "1.4";

  goPackagePath = "github.com/jonnenauha/prometheus_varnish_exporter";

  src = fetchFromGitHub {
    owner = "jonnenauha";
    repo = "prometheus_varnish_exporter";
    rev = version;
    sha256 = "12gd09858zlhn8gkkchfwxv0ca2r72s18wrsz0agfr8pd1gxqh6j";
  };

  goDeps = ./varnish-exporter_deps.nix;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $bin/bin/prometheus_varnish_exporter \
      --prefix PATH : "${varnish}/bin"
  '';

  doCheck = true;

  meta = {
    homepage = https://github.com/jonnenauha/prometheus_varnish_exporter;
    description = "Varnish exporter for Prometheus";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ MostAwesomeDude willibutz ];
  };
}