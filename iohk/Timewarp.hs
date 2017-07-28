{-# LANGUAGE OverloadedStrings, RecordWildCards #-}

module Timewarp where

import Control.Monad (forM_)
import Data.Monoid ((<>))
import Data.Yaml (decodeFile)
import Filesystem.Path.CurrentOS (encodeString)
import GHC.Conc (threadDelay)
import Prelude hiding (FilePath)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Turtle

import NixOps


args = " -d time-warp" <> nixpath
nixpath = " -I ~/ "
deployment = " deployments/timewarp.nix "

runexperiment :: Options -> NixopsConfig -> IO ()
runexperiment o c = do
  -- build
  --checkstatus
  --deploy
  sshForEach o c ["systemctl", "stop", "timewarp"]
  sshForEach o c ["rm", "-f", "/home/timewarp/node.log"]
  nodes <- getNodeNames o c
  sshForEach o c ["systemctl", "start", "timewarp"]
  threadDelay (150*1000000)
  dt <- dumpLogs o c False nodes
  TIO.putStrLn $ "Log dir: tw_experiments/" <> dt


dumpLogs :: Options -> NixopsConfig -> Bool ->  [NodeName] -> IO Text
dumpLogs o c withProf nodes = do
    TIO.putStrLn $ "WithProf: " <> T.pack (show withProf)
    when withProf $ do
        echo "Stopping nodes..."
        sshForEach o c ["systemctl", "stop", "timewarp"]
        sleep 2
        echo "Dumping logs..."
    (_, dt) <- fmap T.strip <$> shellStrict "date +%F_%H%M%S" empty
    let workDir = "tw_experiments/" <> dt
    TIO.putStrLn workDir
    shell ("mkdir -p " <> workDir) empty
    parallelIO o $ fmap (dump workDir) nodes 
    return dt
  where
    dump workDir node = do
        forM_ logs $ \(rpath, fname) -> do
          scpFromNode o c node rpath (workDir <> "/" <> fname (fromNodeName node))
    logs = mconcat
             [ if withProf
                  then profLogs
                  else []
             , defLogs
             ]
defLogs =
    [ ("/home/timewarp/node.log", (<> ".log"))
    , ("/var/log/saALL", (<> ".sar"))
    ]
profLogs =
    [ 
    --  ("/var/lib/cardano-node/cardano-node.prof", (<> ".prof"))
    --, ("/var/lib/cardano-node/cardano-node.hp", (<> ".hp"))
    ---- in fact, if there's a heap profile then there's no eventlog and vice versa
    ---- but scp will just say "not found" and it's all good
    --, ("/var/lib/cardano-node/cardano-node.eventlog", (<> ".eventlog"))
    ]
