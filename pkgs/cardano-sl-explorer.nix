{ mkDerivation, aeson, base, base16-bytestring, binary, bytestring
, cardano-sl, cardano-sl-core, cardano-sl-db, cardano-sl-infra
, cardano-sl-ssc, cardano-sl-update, containers, cpphs, either
, engine-io, engine-io-snap, engine-io-wai, ether, exceptions
, fetchgit, formatting, lens, lifted-base, log-warper
, monad-control, monad-loops, mtl, network-transport-tcp
, node-sketch, optparse-simple, purescript-bridge, serokell-util
, servant, servant-multipart, servant-server, servant-swagger
, servant-swagger-ui, snap-core, snap-cors, snap-server, socket-io
, stdenv, stm, swagger2, tagged, text, text-format, time
, time-units, transformers, universum, unordered-containers, wai
, warp
}:
mkDerivation {
  pname = "cardano-sl-explorer";
  version = "0.1.0";
  src = fetchgit {
    url = "https://github.com/input-output-hk/cardano-sl-explorer.git";
    sha256 = "0kbzqm19a6yqngqqw07m8sz0ql9f2mbv10w68xqn1csqmx8p9i7d";
    rev = "c2afafc92d0d90ec8b0135814f41638b89cd70ed";
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    aeson base base16-bytestring binary bytestring cardano-sl
    cardano-sl-core cardano-sl-db cardano-sl-infra cardano-sl-ssc
    containers either engine-io engine-io-snap engine-io-wai ether
    exceptions formatting lens lifted-base log-warper monad-control
    monad-loops mtl node-sketch serokell-util servant servant-server
    snap-core snap-cors snap-server socket-io stm tagged text
    text-format time time-units transformers universum
    unordered-containers wai warp
  ];
  libraryToolDepends = [ cpphs ];
  executableHaskellDepends = [
    aeson base bytestring cardano-sl cardano-sl-core cardano-sl-infra
    cardano-sl-ssc cardano-sl-update containers ether formatting lens
    log-warper mtl network-transport-tcp node-sketch optparse-simple
    purescript-bridge serokell-util servant-multipart servant-server
    servant-swagger servant-swagger-ui swagger2 text time time-units
    universum
  ];
  executableToolDepends = [ cpphs ];
  doCheck = false;
  description = "Cardano explorer";
  license = stdenv.lib.licenses.mit;
}
