rec {
  # Compile time settings
  genesisN = 6;
  slotDuration = 20;
  networkDiameter = 15;
  mpcRelayInterval = 45;

  # Run time settings
  bitcoinOverFlat = false;
  totalMoneyAmount = 60000000;
  richPoorDistr = false;
  nodePort = 3000;
  enableP2P = true;

  txgenR = 1;
  txgenN = 3;
  txgenPause = 0;
  txgenInitTps = 5;
  txgenTpsStep = 5;
  txgenP = 2;
  txgenAddresses = [ 0 ];
  #txgenMofN = [ 3 5 ];

  # Delegation settings
  enableDelegation = false;
  #enableDelegation = true;
  delegationNode = 0;

  productionMode = false;
  systemStart = 1499246772;
}
