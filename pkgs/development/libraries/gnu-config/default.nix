{ stdenv, fetchurl }:

let
  rev = "b75cdc942a6172f63b34faf642b8c797239f6776";

  # Don't use fetchgit as this is needed during Aarch64 bootstrapping
  configGuess = fetchurl {
    url = "http://git.savannah.gnu.org/cgit/config.git/plain/config.guess?id=${rev}";
    sha256 = "1bb8z1wzjs81p9qrvji4bc2a8zyxjinz90k8xq7sxxdp6zrmq1sv";
  };
  configSub = fetchurl {
    url = "http://git.savannah.gnu.org/cgit/config.git/plain/config.sub?id=${rev}";
    sha256 = "00dn5i2cp4iqap5vr368r5ifrgcjfq5pr97i4dkkdbha1han5hsc";
  };
in
stdenv.mkDerivation rec {
  name = "gnu-config-${version}";
  version = "2016-12-31";

  buildCommand = ''
    mkdir -p $out
    cp ${configGuess} $out/config.guess
    cp ${configSub} $out/config.sub
  '';

  meta = with stdenv.lib; {
    description = "Attempt to guess a canonical system name";
    homepage = http://savannah.gnu.org/projects/config;
    license = licenses.gpl3;
    # In addition to GPLv3:
    #   As a special exception to the GNU General Public License, if you
    #   distribute this file as part of a program that contains a
    #   configuration script generated by Autoconf, you may include it under
    #   the same distribution terms that you use for the rest of that
    #   program.
    maintainers = [ maintainers.dezgeg ];
    platforms = platforms.all;
  };
}