{ stdenv, remixIdeSrc, solcBinSrc, pkgs }:

with pkgs;

stdenv.mkDerivation {
  src = remixIdeSrc;

  name = "remix-ide";

  buildInputs = [ nodejs-9_x git cacert python wget solcBinSrc ];

  patches = [
    ./remix-ide.patch
  ];

  configurePhase = ''
    export HOME="$NIX_BUILD_TOP"
    npm install
  '';

  buildPhase = ''
    npm run linkremixcore
    npm run linkremixlib
    npm run linkremixsolidity
    npm run build
  '';

  installPhase = ''
    mv build $out
    ln -s ${solcBinSrc} $out/solc-bin
    cp -r index.html soljson.js assets $out/
    substituteInPlace $out/index.html \
      --replace "build/app.js" "app.js" \
      --replace "UA-XXXXXXXXX-X" "UA-119953429-5"
  '';
}
