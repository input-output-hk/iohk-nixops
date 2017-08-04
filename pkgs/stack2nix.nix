{ mkDerivation, async, base, bytestring, Cabal, containers
, data-fix, directory, fetchgit, filepath, Glob, hnix
, monad-parallel, optparse-applicative, process, SafeSemaphore
, stdenv, temporary, text, yaml
}:
mkDerivation {
  pname = "stack2nix";
  version = "0.1.3.0";
  src = fetchgit {
    url = "https://github.com/input-output-hk/stack2nix.git";
    sha256 = "0cc3w5bhazllj2g9fw6fmhya71lklplkqlvyl0jm4qm9rmq3280m";
    rev = "b26d16d1be42e30083a29fd593daba535d44d736";
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    async base bytestring Cabal containers data-fix directory filepath
    Glob hnix monad-parallel process SafeSemaphore temporary text yaml
  ];
  executableHaskellDepends = [ base Cabal optparse-applicative ];
  doCheck = false;
  description = "Convert stack.yaml files into Nix build instructions.";
  license = stdenv.lib.licenses.mit;
}
