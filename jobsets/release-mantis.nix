{ nixpkgs
, sbtVerifySrc
, mantisSrc
, kevmSrc
, secp256k1Src
, soliditySrc
, solidityServiceSrc
, solcBinSrc
, remixIdeSrc
, ieleSrc
, ...
}:
with import nixpkgs {};
rec {
  sbtVerify = callPackage ./sbt-verify.nix {
    inherit sbtVerifySrc;
  };

  mantis = callPackage ./mantis.nix {
    inherit mantisSrc;
    inherit sbtVerify;
  };

  kevm = pkgs.callPackage ./kevm.nix {
    inherit kevmSrc;
  };

  secp256k1 = callPackage ./secp256k1.nix {
    inherit secp256k1Src;
  };

  iele = callPackage ./iele.nix {
    inherit ieleSrc secp256k1;
  };

  solidity = callPackage ./solidity.nix {
    inherit iele soliditySrc;
  };

  solidityService = callPackage ./solidity-service.nix {
    inherit solidity iele solidityServiceSrc;
  };

  remixIde = callPackage ./remix-ide.nix {
    inherit solcBinSrc remixIdeSrc;
  };
}
