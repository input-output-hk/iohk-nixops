{ mkDerivation, async, base, bytestring, containers, data-fix
, directory, fetchgit, filepath, Glob, hnix, monad-parallel
, optparse-applicative, process, SafeSemaphore, stdenv, temporary
, text, yaml
}:
mkDerivation {
  pname = "stack2nix";
  version = "0.1.0.0";
  src = fetchgit {
    url = "https://github.com/input-output-hk/stack2nix.git";
    sha256 = "1vc8w9b7i4wr1jx5zj7kvxj1901ck15scj3556h8j8c64g6ppr8k";
    rev = "8f087b92f83be078e8cfe86fb243121dca4601ba";
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    async base bytestring containers data-fix directory filepath Glob
    hnix monad-parallel process SafeSemaphore temporary text yaml
  ];
  executableHaskellDepends = [ base optparse-applicative ];
  doCheck = false;
  description = "Convert stack.yaml files into Nix build instructions.";
  license = stdenv.lib.licenses.bsd3;
}
