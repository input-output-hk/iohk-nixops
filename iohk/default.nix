{ mkDerivation, stdenv
,   aeson, amazonka, amazonka-core, amazonka-ec2, amazonka-iam, base, bytestring, cassava, conduit, containers
,   exceptions, lens, lens-aeson, mtl, old-locale, optional-args, random, resourcet, safe, system-filepath
,   text, text-format, time, tinylog, turtle, utf8-string, vector, yaml
# non-haskell
, awscli, nix-prefetch-scripts, wget
}:
mkDerivation {
  pname = "iohk-ops";
  version = "0.1.0.0";
  src = ./..;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    aeson  amazonka  amazonka-core  amazonka-ec2  amazonka-iam  base  bytestring  cassava  conduit  containers
    exceptions  lens  lens-aeson  mtl  old-locale  optional-args  random  resourcet  safe  system-filepath
    text  text-format  time  tinylog  turtle  utf8-string vector  yaml
    # non-haskell
    awscli nix-prefetch-scripts wget
  ];
  license = stdenv.lib.licenses.bsd3;
}
