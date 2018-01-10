{ mkDerivation, aeson, aeson-pretty, amazonka, amazonka-s3
, ansi-terminal, base, bytestring, cassava, containers, directory
, dns, filepath, git, hourglass, hspec, http-client
, http-client-tls, http-types, lens, lens-aeson, managed, mtl
, optional-args, optparse-applicative, resourcet, safe, stdenv
, system-filepath, text, turtle, universum, unix
, unordered-containers, utf8-string, vector, yaml
}:
mkDerivation {
  pname = "iohk-ops";
  version = "0.1.0.0";
  src = ./.;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    aeson aeson-pretty amazonka amazonka-s3 ansi-terminal base
    bytestring cassava containers directory dns filepath git hourglass
    http-client http-client-tls http-types lens lens-aeson managed mtl
    optional-args optparse-applicative resourcet safe system-filepath
    text turtle unix unordered-containers utf8-string vector yaml
  ];
  testHaskellDepends = [
    aeson amazonka amazonka-s3 ansi-terminal base bytestring cassava
    directory git hspec http-client http-client-tls http-types lens
    managed resourcet system-filepath text turtle universum
    unordered-containers yaml
  ];
  license = stdenv.lib.licenses.bsd3;
}
