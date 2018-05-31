{ stdenv, fetchurl, zlib, interactive ? false, readline ? null, ncurses ? null }:

assert interactive -> readline != null && ncurses != null;

with stdenv.lib;

let
  archiveVersion = import ./archive-version.nix stdenv.lib;
in

stdenv.mkDerivation rec {
  name = "sqlite-${version}";
  version = "3.23.1";

  # NB! Make sure to update analyzer.nix src (in the same directory).
  src = fetchurl {
    url = "https://sqlite.org/2018/sqlite-autoconf-${archiveVersion version}.tar.gz";
    sha256 = "09ggapjhqjb2pzk0wkfczil77plijg3d77m2bpzlwx2y7ql2p14j";
  };

  outputs = [ "bin" "dev" "out" ];
  separateDebugInfo = stdenv.isLinux;

  buildInputs = [ zlib ] ++ optionals interactive [ readline ncurses ];

  configureFlags = [ "--enable-threadsafe" ] ++ optional interactive "--enable-readline";

  NIX_CFLAGS_COMPILE = [
    "-DSQLITE_ENABLE_COLUMN_METADATA"
    "-DSQLITE_ENABLE_DBSTAT_VTAB"
    "-DSQLITE_ENABLE_JSON1"
    "-DSQLITE_ENABLE_FTS3"
    "-DSQLITE_ENABLE_FTS3_PARENTHESIS"
    "-DSQLITE_ENABLE_FTS3_TOKENIZER"
    "-DSQLITE_ENABLE_FTS4"
    "-DSQLITE_ENABLE_FTS5"
    "-DSQLITE_ENABLE_RTREE"
    "-DSQLITE_ENABLE_STMT_SCANSTATUS"
    "-DSQLITE_ENABLE_UNLOCK_NOTIFY"
    "-DSQLITE_SOUNDEX"
    "-DSQLITE_SECURE_DELETE"
    "-DSQLITE_MAX_VARIABLE_NUMBER=250000"
    "-DSQLITE_MAX_EXPR_DEPTH=10000"
  ];

  # Test for features which may not be available at compile time
  preBuild = ''
    # Use pread(), pread64(), pwrite(), pwrite64() functions for better performance if they are available.
    if cc -Werror=implicit-function-declaration -x c - -o "$TMPDIR/pread_pwrite_test" <<< \
      ''$'#include <unistd.h>\nint main()\n{\n  pread(0, NULL, 0, 0);\n  pwrite(0, NULL, 0, 0);\n  return 0;\n}'; then
      export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -DUSE_PREAD"
    fi
    if cc -Werror=implicit-function-declaration -x c - -o "$TMPDIR/pread64_pwrite64_test" <<< \
      ''$'#include <unistd.h>\nint main()\n{\n  pread64(0, NULL, 0, 0);\n  pwrite64(0, NULL, 0, 0);\n  return 0;\n}'; then
      export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -DUSE_PREAD64"
    elif cc -D_LARGEFILE64_SOURCE -Werror=implicit-function-declaration -x c - -o "$TMPDIR/pread64_pwrite64_test" <<< \
      ''$'#include <unistd.h>\nint main()\n{\n  pread64(0, NULL, 0, 0);\n  pwrite64(0, NULL, 0, 0);\n  return 0;\n}'; then
      export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -DUSE_PREAD64 -D_LARGEFILE64_SOURCE"
    fi

    # Necessary for FTS5 on Linux
    export NIX_LDFLAGS="$NIX_LDFLAGS -lm"

    echo ""
    echo "NIX_CFLAGS_COMPILE = $NIX_CFLAGS_COMPILE"
    echo ""
  '';

  meta = {
    description = "A self-contained, serverless, zero-configuration, transactional SQL database engine";
    downloadPage = http://sqlite.org/download.html;
    homepage = http://www.sqlite.org/;
    maintainers = with maintainers; [ eelco np ];
    platforms = platforms.unix;
  };
}