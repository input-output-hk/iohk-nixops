#!/usr/bin/env nix-shell
#! nix-shell -j 4 -i runhaskell -p 'pkgs.haskellPackages.ghcWithPackages (hp: with hp; [ turtle cassava vector safe aeson yaml lens-aeson ])'
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/f2c4af4e3bd9ecd4b1cf494270eae5fd3ca9e68c.tar.gz

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections   #-}
{-# LANGUAGE ViewPatterns   #-}

import Control.Monad.Except (ExceptT (..), runExceptT)
import Turtle hiding (printf)
import Prelude hiding (FilePath)
import Control.Monad (forM_, void, when)
import Control.Monad.Trans(lift)
import Control.Lens
import Filesystem.Path.CurrentOS (encodeString)
import Data.Aeson
import Data.Aeson.Lens
import qualified Data.List as L
import Data.Maybe (catMaybes, fromJust)
import Data.Monoid ((<>))
import Data.Yaml (decodeFile)
import Data.Text.Lazy (fromStrict)
import Data.Text.IO as TIO
import Data.Text.Lazy.Encoding (encodeUtf8)
import qualified Data.Text as T
import GHC.Generics
import Text.Printf
import Text.Read (readMaybe)
import qualified Data.Map as M

import NixOps


-- CLI Parser

data Command =
    Deploy
  | Create
  | Destroy
  | FromScratch
  | CheckStatus
  | RunExperiment
  | PostExperiment
  | Build
  | DumpLogs { withProf :: Bool }
  | Start
  | Stop
  | FirewallBlock { fromRegion :: Text, toRegion :: Text }
  | FirewallClear
  | AMI
  | PrintDate
  | GenerateIPDHTMappings
  deriving (Show)

subparser :: Parser Command
subparser =
      subcommand "deploy" "Deploy the whole cluster" (pure Deploy)
  <|> subcommand "create" "Create the whole cluster" (pure Create)
  <|> subcommand "destroy" "Destroy the whole cluster" (pure Destroy)
  <|> subcommand "build" "Build the application" (pure Build)
  <|> subcommand "fromscratch" "Destroy, Delete, Create, Deploy" (pure FromScratch)
  <|> subcommand "checkstatus" "Check if nodes are accessible via ssh and reboot if they timeout" (pure CheckStatus)
  <|> subcommand "runexperiment" "Deploy cluster and perform measurements" (pure RunExperiment)
  <|> subcommand "postexperiment" "Post-experiments logs dumping (if failed)" (pure PostExperiment)
  <|> subcommand "dumplogs" "Dump logs" (DumpLogs <$> switch "prof" 'p' "Dump profiling data as well (requires service stop)")
  <|> subcommand "stop" "Stop cardano-node service" (pure Stop)
  <|> subcommand "start" "Start cardano-node service" (pure Start)
  <|> subcommand "date" "Print date/time" (pure PrintDate)
  <|> subcommand "firewall-block-region" "Block whole region in firewall" (FirewallBlock <$> optText "from-region" 'f' "AWS Region that won't reach --to" <*> optText "to-region" 't' "AWS Region that all nodes will be blocked")
  <|> subcommand "firewall-clear" "Clear firewall" (pure FirewallClear)
  <|> subcommand "ami" "Build ami" (pure AMI)
  <|> subcommand "generate-ipdht" "Generate IP/DHT mappings for wallet use" (pure GenerateIPDHTMappings)

parser :: Parser (Options, Command)
parser = (,) <$> optionsParser
             <*> subparser

main :: IO ()
main = do
  (opts@Options{..}, command) <- options "Helper CLI around NixOps to run experiments" parser
  Just c <- decodeFile $ encodeString oConfigFile
  --dat <- fmap toNodesInfo <$> info c
  dat <- getSmartGenCmd c
  TIO.putStrLn $ T.pack $ show dat
  let isNode (T.unpack . getNodeName -> ('n':'o':'d':'e':_)) = True
      isNode _ = False
      getNodeNames' = filter isNode <$> getNodeNames c
  case command of
    Deploy         -> deploy      opts c
    Create         -> create      opts c
    Destroy        -> destroy     opts c
    FromScratch    -> fromscratch opts c
    CheckStatus    -> checkstatus c
    RunExperiment  -> getNodeNames' >>= runexperiment c
    PostExperiment -> postexperiment c
    Build -> build c
    DumpLogs {..} -> getNodeNames' >>= void . dumpLogs c withProf
    Start -> getNodeNames' >>= startCardanoNodes c
    Stop -> getNodeNames' >>= stopCardanoNodes c
    AMI -> buildAMI c
    PrintDate -> getNodeNames' >>= printDate c
    FirewallBlock from to -> firewallBlock c from to
    FirewallClear -> firewallClear c
    GenerateIPDHTMappings -> void $ generateIPDHTMappings c
    -- TODO: invoke nixops with passed parameters


-- CLI Commands


buildAMI :: NixOpsConfig -> IO ()
buildAMI c = do
  shells ("nix-build jobsets/cardano.nix -A cardano-node-image -o image -I " <> nixPath c) empty
  shells "./scripts/create-amis.sh" empty

build :: NixOpsConfig -> IO ()
build c = do
  TIO.putStrLn "Building derivation..."
  shells ("nix-build -j 4 --cores 2 default.nix -A cardano-sl-static -I " <> nixPath c) empty

firewallClear ::  NixOpsConfig -> IO ()
firewallClear c = sshForEach c "iptables -F"

firewallBlock ::  NixOpsConfig -> Text -> Text -> IO ()
firewallBlock c from to = do
  nodes <- getNodes c
  let fromNodes = filter (f from) nodes
  let toNodes = filter (f to) nodes
  TIO.putStrLn $ "Blocking nodes: " <> (T.intercalate ", " $ fmap (getNodeName . diName) toNodes)
  TIO.putStrLn $ "Applying on nodes: " <> (T.intercalate ", " $ fmap (getNodeName . diName) fromNodes)
  parallelIO $ fmap (g toNodes) fromNodes
    where
      f s node = T.isInfixOf ("[" <> s) (diType node)
      g toNodes node = ssh c ("'for ip in " <> ips toNodes <> "; do iptables -A INPUT -s $ip -j DROP;done'") $ diName node
      ips = T.intercalate " " . fmap (getIP . diPublicIP)

runexperiment :: NixOpsConfig -> [NodeName] -> IO ()
runexperiment c nodes = do
  -- build
  echo "Checking nodes' status, rebooting failed"
  checkstatus c
  --deploy
  echo "Stopping nodes..."
  stopCardanoNodes c nodes
  echo "Starting nodes..."
  startCardanoNodes c nodes
  echo "Delaying... (40s)"
  sleep 40
  config <- either error id <$> getConfig
  when (enableDelegation config) $ do
    echo "Launching wallet to send delegation certs"
    shells "rm -f wallet.log wallet.json" empty
    cliCmd <- getWalletDelegationCmd c
    shells (cliCmd <> " | awk '{print}; /Command execution finished/ {exit}'") empty
    echo "Delaying... (40s)"
    sleep 40
  echo "Launching txgen"
  shells "rm -f timestampsTxSender.json txgen.log txgen.json smart-gen-verifications*.csv smart-gen-tps.csv" empty
  cliCmd <- getSmartGenCmd c
  shells cliCmd empty
  echo "Delaying... (150s)"
  sleep 150
  postexperiment c

postexperiment :: NixOpsConfig -> IO ()
postexperiment c = do
  nodes <- getNodeNames c
  echo "Checking nodes' status, rebooting failed"
  checkstatus c
  echo "Retreive logs..."
  dt <- dumpLogs c True nodes
  cliCmd <- getSmartGenCmd c
  let dirname = "./experiments/" <> dt
  shells ("echo \"" <> cliCmd <> "\" > " <> dirname <> "/txCommandLine") empty
  shells ("echo -n \"cardano-sl revision: \" > " <> dirname <> "/revisions.info") empty
  shells ("cat pkgs/cardano-sl.nix | grep rev >> " <> dirname <> "/revisions.info") empty
  shells ("echo -n \"time-warp revision: \" >> " <> dirname <> "/revisions.info") empty
  shells ("cat kgs/time-warp.nix | grep rev >> " <> dirname <> "/revisions.info") empty
  shells ("cp config.nix " <> dirname) empty
  shells ("mv txgen* smart* " <> dirname) empty
  --shells (foldl (\s n -> s <> " --file " <> n <> ".json") ("sh -c 'cd " <> workDir <> "; ./result/bin/cardano-analyzer --tx-file timestampsTxSender.json") nodes <> "'") empty
  shells ("tar -czf experiments/" <> dt <> ".tgz experiments/" <> dt) empty

dumpLogs :: NixOpsConfig -> Bool -> [NodeName] -> IO Text
dumpLogs c withProf nodes = do
    TIO.putStrLn $ "WithProf: " <> T.pack (show withProf)
    when withProf $ do
        echo "Stopping nodes..."
        stopCardanoNodes c nodes
        sleep 2
        echo "Dumping logs..."
    (_, dt) <- fmap T.strip <$> shellStrict "date +%F_%H%M%S" empty
    let workDir = "experiments/" <> dt
    TIO.putStrLn workDir
    shell ("mkdir -p " <> workDir) empty
    parallelIO $ fmap (dump workDir) nodes
    return dt
  where
    dump workDir node =
        forM_ logs $ \(rpath, fname) -> do
          scpFromNode c node rpath (workDir <> "/" <> fname (getNodeName node))
    logs = mconcat
             [ if withProf
                  then profLogs
                  else []
             , defLogs
             ]

generateIPDHTMappings :: NixOpsConfig -> IO Text
generateIPDHTMappings c = runError $ do
  nodes <- ExceptT $ getNodesMap c
  config@Config{..} <- ExceptT $ getConfig
  let peers = genPeers nodePort (M.toList nodes)
  lift $ TIO.putStrLn $ T.unlines peers
  return $ T.unlines peers
-- Rest


getNodesMap :: NixOpsConfig -> IO (Either String (M.Map Int DeploymentInfo))
getNodesMap c = (toMap <=< fmap toNodesInfo) <$> info c
  where
    toMap :: [DeploymentInfo] -> Either String (M.Map Int DeploymentInfo)
    toMap = fmap M.fromList . sequenceA .
            map (\d -> (,d) <$> extractName
                                (T.unpack . getNodeName $ diName d))
    extractName = maybe (Left  "Bad node name") Right .
                  (L.stripPrefix "node" >=> readMaybe)

runError :: ExceptT String IO Text -> IO Text
runError action = runExceptT action >>=
  either (\(T.pack -> err) -> TIO.putStrLn err >> return err) pure

show' :: Show a => a -> Text
show' = T.pack . show

getSmartGenCmd :: NixOpsConfig -> IO Text
getSmartGenCmd c = runError $ do
  nodes <- ExceptT $ getNodesMap c
  config@Config{..} <- ExceptT $ getConfig
  dhtfile <- lift $ Prelude.readFile "static/dht.json"
  peers <- ExceptT $ return $ getPeers c config dhtfile nodes
  (_, sgIp) <- fmap T.strip <$> shellStrict ("curl " <> myIpUrl) empty
  let sgDhtKey = fromJust $ dhtfile ^? key "node100" . _String

  let bot = if bitcoinOverFlat then "bitcoin" else "flat"
      recipShare = "0.5"
      cliCmd = mconcat [ "./result/bin/cardano-smart-generator"
                       --, " +RTS -N -pa -hc -T -A4G -qg -RTS"
                       , " +RTS -N -A4G -qg -RTS"
                       , (T.pack . mconcat $ map (\i -> " -i " <> show i) txgenAddresses)
                       , if enableP2P
                         then " --explicit-initial --disable-propagation "
                         else ""
                       , peers
                       , " -R ", show' txgenR," -N ", show' txgenN," -p ", show' txgenPause
                       , " --init-money ", show' totalMoneyAmount
                       , " -t ", show' txgenInitTps, " -S ", show' txgenTpsStep, " -P ", show' txgenP
                       , " --recipients-share " <> if enableP2P then recipShare else "1"
                       , " --log-config static/txgen-logging-warnonly.yaml"
                       , " --json-log=txgen.json"
                       , " --listen " <> sgIp <> ":24962"
                       -- , " --dht-key " <> sgDhtKey
                       , " --", bot, "-distr '(", show' genesisN, ",", show' totalMoneyAmount, ")'"
                       ]
  return cliCmd


genDhtKey :: Int -> Text
genDhtKey i = "MHdrsP-oPf7UWl" <> (T.pack $ printf "%.3d" i) <> "7QuXnLK5RD="

genPeers :: Int -> [(Int, DeploymentInfo)] -> [Text]
genPeers port = map impl
  where
    impl (i, getIP . diPublicIP -> ip) = ip <> ":" <> show' port 

getPeers :: NixOpsConfig -> Config -> String -> M.Map Int DeploymentInfo -> Either String Text
getPeers c config dhtfile nodes = do
  case M.lookup 0 nodes of
    Nothing -> Left "Node0 retrieval failed"
    Just node0 -> let port = nodePort config
                      infos = if enableP2P config then [(0, node0)] else M.toList nodes
                  in Right $ mconcat $ map (\p -> " --kademlia-peer " <> p) $ genPeers port infos

getWalletDelegationCmd :: NixOpsConfig -> IO Text
getWalletDelegationCmd c = runError $ do
  nodes <- ExceptT $ getNodesMap c
  config@Config{..} <- ExceptT $ getConfig
  dhtfile <- lift $ Prelude.readFile "static/dht.json"
  peers <- ExceptT $ return $ getPeers c config dhtfile nodes

  let mkCmd i = "delegate-light " <> show' i <> " " <> show' delegationNode
      cmds = T.intercalate "," $ map mkCmd $ filter (/= delegationNode) $ M.keys nodes
      bot = if bitcoinOverFlat then "bitcoin" else "flat"
      cliCmd = mconcat [ "./result/bin/cardano-wallet"
                       --, " +RTS -N -pa -hc -T -A4G -qg -RTS"
                       , " +RTS -N -A4G -qg -RTS"
                       , if enableP2P
                         then " --explicit-initial --disable-propagation "
                         else ""
                       , peers
                       , " --log-config static/wallet-logging.yaml"
                       , " --json-log=wallet.json"
                       , " --", bot, "-distr '(", show' genesisN, ",", show' totalMoneyAmount, ")'"
                       , " cmd --commands \"", cmds, "\""
                       ]

  return cliCmd

defLogs =
    [ ("/var/lib/cardano-node/node.log", (<> ".log"))
    , ("/var/lib/cardano-node/jsonLog.json", (<> ".json"))
    , ("/var/lib/cardano-node/time-slave.log", (<> "-ts.log"))
    , ("/var/log/saALL", (<> ".sar"))
    ]
profLogs =
    [ ("/var/lib/cardano-node/cardano-node.prof", (<> ".prof"))
    , ("/var/lib/cardano-node/cardano-node.hp", (<> ".hp"))
    -- in fact, if there's a heap profile then there's no eventlog and vice versa
    -- but scp will just say "not found" and it's all good
    , ("/var/lib/cardano-node/cardano-node.eventlog", (<> ".eventlog"))
    ]


printDate :: NixOpsConfig -> [NodeName] -> IO ()
printDate c nodes = parallelIO $ fmap f nodes
  where
    f n = ssh' c (\s -> TIO.putStrLn $ "Date on " <> getNodeName n <> ": " <> s) "date" n

stopCardanoNodes :: NixOpsConfig -> [NodeName] -> IO ()
stopCardanoNodes c nodes = parallelIO $ fmap (ssh c "systemctl stop cardano-node") nodes

startCardanoNodes :: NixOpsConfig -> [NodeName] -> IO ()
startCardanoNodes c nodes =
  parallelIO $ fmap (ssh c $ "'" <> rmCmd <> ";" <> startCmd <> "'") nodes
  where
    rmCmd = foldl (\s (f, _) -> s <> " " <> f) "rm -f" logs
    startCmd = "systemctl start cardano-node"
    logs = mconcat [ defLogs, profLogs ]


-- Cardano Config


data Config = Config
  { bitcoinOverFlat :: Bool
  , totalMoneyAmount :: Int
  , nodePort :: Int
  , genesisN :: Int
  , mpcRelayInterval :: Int
  , networkDiameter :: Int
  , slotDuration :: Int
  , enableP2P :: Bool
  , txgenR :: Int
  , txgenN :: Int
  , txgenPause :: Int
  , txgenP :: Int
  , txgenInitTps :: Int
  , txgenTpsStep :: Int
  , txgenAddresses :: [Int]
  , enableDelegation :: Bool
  , delegationNode :: Int
  } deriving (Generic, Show)

instance FromJSON Config

getConfig :: IO (Either String Config)
getConfig = do
  (exitcode, output) <- shellStrict "nix-instantiate --eval --strict --json config.nix" empty
  return $ eitherDecode (encodeUtf8 $ fromStrict output)
