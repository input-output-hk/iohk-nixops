{ solidityServiceSrc
, solidity
, iele
, callPackage
}:

(callPackage solidityServiceSrc { inherit solidity iele; })."solidity-service"
