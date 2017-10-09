#!/usr/bin/env runhaskell
{-# LANGUAGE DeriveGeneric, GADTs, LambdaCase, OverloadedStrings, RecordWildCards, StandaloneDeriving, TupleSections, ViewPatterns #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults #-}

import           Control.Monad                    (forM_)
import           Data.Char                        (toLower)
import           Data.List
import qualified Data.Map                      as Map
import           Data.Maybe
import           Data.Monoid                      ((<>))
import           Data.Optional                    (Optional)
import qualified Data.Text                     as T
import qualified Filesystem.Path.CurrentOS     as Path
import qualified System.Environment            as Sys
import           Turtle                    hiding (env, err, fold, inproc, prefix, procs, shells, e, f, o, x)
import           Time.Types
import           Time.System


import           NixOps
import qualified NixOps                        as Ops
import qualified CardanoCSL                    as Cardano
import           Topology


-- * Elementary parsers
--
-- | Given a string, either return a constructor that being 'show'n case-insensitively matches the string,
--   or raise an error, explaining what went wrong.
diagReadCaseInsensitive :: (Bounded a, Enum a, Read a, Show a) => String -> Maybe a
diagReadCaseInsensitive str = diagRead $ toLower <$> str
  where mapping    = Map.fromList [ (toLower <$> show x, x) | x <- every ]
        diagRead x = Just $ flip fromMaybe (Map.lookup x mapping)
                     (errorT $ format ("Couldn't parse '"%s%"' as one of: "%s%"\n")
                                        (T.pack str) (T.pack $ intercalate ", " $ Map.keys mapping))

optReadLower :: (Bounded a, Enum a, Read a, Show a) => ArgName -> ShortName -> Optional HelpMessage -> Parser a
optReadLower = opt (diagReadCaseInsensitive . T.unpack)
argReadLower :: (Bounded a, Enum a, Read a, Show a) => ArgName -> Optional HelpMessage -> Parser a
argReadLower = arg (diagReadCaseInsensitive . T.unpack)

parserConfigurationKey :: Parser ConfigurationKey
parserConfigurationKey = ConfigurationKey <$> (optText "configuration-key" 'k' "Configuration key.  Default: env-specific.")

parserEnvironment :: Parser Environment
parserEnvironment = fromMaybe Ops.defaultEnvironment <$> optional (optReadLower "environment" 'e' $ pure $
                                                                   Turtle.HelpMessage $ "Environment: "
                                                                   <> T.intercalate ", " (lowerShowT <$> (every :: [Environment])) <> ".  Default: development")

parserTarget      :: Parser Target
parserTarget      = fromMaybe Ops.defaultTarget      <$> optional (optReadLower "target"      't' "Target: aws, all;  defaults to AWS")

parserProject     :: Parser Project
parserProject     = argReadLower "project" $ pure $ Turtle.HelpMessage ("Project to set version of: " <> T.intercalate ", " (lowerShowT <$> (every :: [Project])))

parserNodeName    :: Parser NodeName
parserNodeName    = NodeName <$> (argText "NODE" $ pure $
                                   Turtle.HelpMessage $ "Node to operate on. Defaults to '" <> (fromNodeName $ Ops.defaultNode) <> "'")

parserDeployment  :: Parser Deployment
parserDeployment  = argReadLower "DEPL" (pure $
                                         Turtle.HelpMessage $ "Deployment, one of: "
                                         <> T.intercalate ", " (lowerShowT <$> (every :: [Deployment])))
parserDeployments :: Parser [Deployment]
parserDeployments = (\(a, b, c, d) -> concat $ maybeToList <$> [a, b, c, d])
                    <$> ((,,,)
                         <$> (optional parserDeployment) <*> (optional parserDeployment) <*> (optional parserDeployment) <*> (optional parserDeployment))

parserConfirmation :: Text -> Parser Confirmation
parserConfirmation question =
  (\case False -> Ask question
         True  -> Confirm)
  <$> switch "confirm" 'y' "Confirm this particular action, don't ask questions."


-- * Central command
--
data Command where

  -- * setup
  Clone                 :: { cBranch      :: Branch } -> Command
  Template              :: { tFile        :: Maybe Turtle.FilePath
                           , tNixops      :: Maybe Turtle.FilePath
                           , tGenesis     :: Maybe Turtle.FilePath
                           , tTopology    :: Maybe Turtle.FilePath
                           , tConfigurationKey :: Maybe ConfigurationKey
                           , tEnvironment :: Environment
                           , tTarget      :: Target
                           , tName        :: NixopsDepl
                           , tDeployments :: [Deployment]
                           } -> Command
  SetRev                :: Project -> Commit -> DoCommit -> Command
  FakeKeys              :: Command

  -- * building
  Genesis               :: Branch -> Command
  GenerateIPDHTMappings :: Command
  Build                 :: Deployment -> Command
  AMI                   :: Command

  -- * cluster lifecycle
  Nixops'               :: NixopsCmd -> [Arg] -> Command
  Create                :: Command
  Modify                :: Command
  Deploy                :: RebuildExplorer -> BuildOnly -> DryRun -> PassCheck -> Maybe Seconds -> Command
  Destroy               :: Command
  Delete                :: Command
  Info                  :: Command

  -- * high-level scenarios
  DeployFull            :: Branch -> Seconds -> NewGenesis -> Maybe Turtle.FilePath -> WipeNodeDBs -> RebuildExplorer -> Validate -> ResumeFailed -> Command
  DeployFullDeployerPhase :: Seconds -> WipeNodeDBs -> RebuildExplorer -> Command
  FromScratch           :: Command
  ReallocateCoreIPs     :: Command

  -- * live cluster ops
  Ssh                   :: Exec -> [Arg] -> Command
  DeployedCommit        :: NodeName -> Command
  CheckStatus           :: Command
  StartForeground       :: Command
  Stop                  :: Command
  RunExperiment         :: Deployment -> Command
  PostExperiment        :: Command
  DumpLogs              :: { depl :: Deployment, withProf :: Bool } -> Command
  CWipeJournals         :: Command
  GetJournals           :: Command
  CWipeNodeDBs          :: Confirmation -> Command
  PrintDate             :: Command
deriving instance Show Command

centralCommandParser :: Parser Command
centralCommandParser =
  (    subcommandGroup "General:"
    [ ("clone",                 "Clone an 'iohk-ops' repository branch",
                                Clone
                                <$> parserBranch "'iohk-ops' branch to checkout")
    , ("template",              "Produce (or update) a checkout of BRANCH with a cluster config YAML file (whose default name depends on the ENVIRONMENT), primed for future operations.",
                                Template
                                <$> optional (optPath "config"        'c' "Override the default, environment-dependent config filename")
                                <*> optional (optPath "nixops"        'n' "Use a specific Nixops binary for this cluster")
                                <*> optional (optPath "genesis"       'g' "Genesis file.  Environment-dependent defaults")
                                <*> optional (optPath "topology"      't' "Cluster configuration.  Defaults to 'topology.yaml'")
                                <*> optional parserConfigurationKey
                                <*> parserEnvironment
                                <*> parserTarget
                                <*> (NixopsDepl <$> argText "NAME"  "Nixops deployment name")
                                <*> parserDeployments)
    , ("set-rev",               "Set commit of PROJECT dependency to COMMIT, and commit the resulting changes",
                                SetRev
                                <$> parserProject
                                <*> parserCommit "Commit to set PROJECT's version to"
                                <*> flag DontCommit "dont-commit" 'n' "Don't commit the *-src.json")
    , ("fake-keys",             "Fake minimum set of keys necessary for a minimum complete deployment (explorer + report-server + nodes)",  pure FakeKeys)
    ]

   <|> subcommandGroup "Build-related:"
    [ ("genesis",               "initiate production of Genesis in cardano-sl/genesis subdir",
                                Genesis
                                <$> parserBranch "'cardano-sl' branch to update with the new genesis")
    , ("generate-ipdht",        "Generate IP/DHT mappings for wallet use",                          pure GenerateIPDHTMappings)
    , ("build",                 "Build the application specified by DEPLOYMENT",                    Build <$> parserDeployment)
    , ("ami",                   "Build ami",                                                        pure AMI) ]

   -- * cluster lifecycle

   <|> subcommandGroup "Cluster lifecycle:"
   [
     -- ("nixops",                "Call 'nixops' with current configuration",
     --                           (Nixops
     --                            <$> (NixopsCmd <$> argText "CMD" "Nixops command to invoke")
     --                            <*> ???)) -- should we switch to optparse-applicative?
     ("create",                 "Create the whole cluster",                                         pure Create)
   , ("modify",                 "Update cluster state with the nix expression changes",             pure Modify)
   , ("deploy",                 "Deploy the whole cluster",
                                Deploy
                                <$> flag NoExplorerRebuild "no-explorer-rebuild" 'n' "Don't rebuild explorer frontend.  WARNING: use this only if you know what you are doing!"
                                <*> flag BuildOnly         "build-only"          'b' "Pass --build-only to 'nixops deploy'"
                                <*> flag DryRun            "dry-run"             'd' "Pass --dry-run to 'nixops deploy'"
                                <*> flag PassCheck         "check"               'c' "Pass --check to 'nixops build'"
                                <*> ((Seconds . (* 60) . fromIntegral <$>)
                                      <$> optional (optInteger "bump-system-start-held-by" 't' "Bump cluster --system-start time, and add this many minutes to delay")))
   , ("destroy",                "Destroy the whole cluster",                                        pure Destroy)
   , ("delete",                 "Unregistr the cluster from NixOps",                                pure Delete)
   , ("fromscratch",            "Destroy, Delete, Create, Deploy",                                  pure FromScratch)
   , ("reallocate-core-ips",    "Destroy elastic IPs corresponding to the nodes listed and redeploy cluster",
                                                                                                    pure ReallocateCoreIPs)
   , ("info",                   "Invoke 'nixops info'",                                             pure Info)
   , ("deploy-full",            "Perform a full remote deployment from the specified Cardano branch, optionally with genesis regeneration",
                                DeployFull
                                <$> parserBranch "'cardano-sl' branch to update & deploy"
                                <*> (Seconds . (* 60) . fromIntegral
                                      <$> (optInteger "bump-system-start-held-by" 't' "Bump cluster --system-start time, and add this many minutes to delay"))
                                <*> flag NewGenesis "new-genesis"           'g' "Generate new genesis"
                                <*> (optional
                                     (optPath "premade-genesis"    'e' "Supply an externally pre-made genesis archive in 'standard' format"))
                                <*> flag WipeNodeDBs       "wipe-node-dbs"         'w' "Wipe node databases"
                                <*> flag NoExplorerRebuild "no-explorer-rebuild"   'n' "Don't rebuild explorer frontend.  WARNING: use this only if you know what you are doing!"
                                <*> flag SkipValidation    "skip-local-validation" 's' "Skip local validation of the current iohk-ops checkout"
                                <*> flag ResumeFailed      "resume"                'r' "Resume a full remote deployment that failed during on-deployer evaluation.  Pass all the same flags")
   , ("deploy-full-deployer-phase", "On-deployer phase of 'deploy-full'",
                                DeployFullDeployerPhase
                                <$> (Seconds . (* 60) . fromIntegral
                                      <$> (optInteger "bump-system-start-held-by" 't' "Bump cluster --system-start time, and add this many minutes to delay"))
                                <*> flag WipeNodeDBs       "wipe-node-dbs"         'w' "Wipe node databases"
                                <*> flag NoExplorerRebuild "no-explorer-rebuild"   'n' "Don't rebuild explorer frontend.  WARNING: use this only if you know what you are doing!")]

   <|> subcommandGroup "Live cluster ops:"
   [ ("deployed-commit",        "Print commit id of 'cardano-node' running on MACHINE of current cluster.",
                                DeployedCommit
                                <$> parserNodeName)
   , ("ssh",                    "Execute a command on cluster nodes.  Use --on to limit",
                                Ssh <$> (Exec <$> (argText "CMD" "")) <*> many (Arg <$> (argText "ARG" "")))
   , ("checkstatus",            "Check if nodes are accessible via ssh and reboot if they timeout", pure CheckStatus)
   , ("start-foreground",       "Start cardano (or explorer) on the specified node (--on), in foreground",
                                 pure StartForeground)
   , ("stop",                   "Stop cardano-node service",                                        pure Stop)
   , ("runexperiment",          "Deploy cluster and perform measurements",                          RunExperiment <$> parserDeployment)
   , ("postexperiment",         "Post-experiments logs dumping (if failed)",                        pure PostExperiment)
   , ("dumplogs",               "Dump logs",
                                DumpLogs
                                <$> parserDeployment
                                <*> switch "prof"         'p' "Dump profiling data as well (requires service stop)")
   , ("wipe-journals",          "Wipe *all* journald logs on cluster",                              pure CWipeJournals)
   , ("get-journals",           "Obtain cardano-node journald logs from cluster",                   pure GetJournals)
   , ("wipe-node-dbs",          "Wipe *all* node databases on cluster (--on limits the scope, though)",
                                CWipeNodeDBs
                                <$> parserConfirmation "Wipe node DBs on the entire cluster?")
   , ("date",                   "Print date/time",                                                  pure PrintDate)]

   <|> subcommandGroup "Other:"
    [ ])


main :: IO ()
main = do
  args <- (Arg . T.pack <$>) <$> Sys.getArgs
  (opts@Options{..}, topcmds) <- options "Helper CLI around IOHK NixOps. For example usage see:\n\n  https://github.com/input-output-hk/internal-documentation/wiki/iohk-ops-reference#example-deployment" $
                     (,) <$> Ops.parserOptions <*> many centralCommandParser
  case oChdir of
    Just path -> cd path
    Nothing   -> pure ()

  forM_ topcmds $ runTop (opts { oChdir = Nothing }) args

runTop :: Options -> [Arg] -> Command -> IO ()
runTop o@Options{..} args topcmd = do
  case topcmd of
    Clone{..}                   -> runClone           o cBranch
    Template{..}                -> runTemplate        o topcmd  args
    SetRev proj comId comm      -> Ops.runSetRev      o proj comId $
                                   if comm == DontCommit then Nothing
                                   else Just $ format ("Bump "%s%" revision to "%s) (lowerShowT proj) (fromCommit comId)

    _ -> do
      -- XXX: Config filename depends on environment, which defaults to 'Development'
      let cf = flip fromMaybe oConfigFile $ Ops.envDefaultConfig $ Ops.envSettings Ops.defaultEnvironment
      c <- Ops.readConfig o cf

      when (toBool oVerbose) $
        printf ("-- command "%s%"\n-- config '"%fp%"'\n") (showT topcmd) cf

      doCommand o c topcmd
    where
        doCommand :: Options -> Ops.NixopsConfig -> Command -> IO ()
        doCommand o@Options{..} c@Ops.NixopsConfig{..} cmd = do
          case cmd of
            -- * setup
            FakeKeys                 -> Ops.runFakeKeys
            -- * building
            Genesis branch           -> void $
                                        Ops.generateOrInsertGenesis   o c branch Nothing
            GenerateIPDHTMappings    -> void $
                                        Cardano.generateIPDHTMappings o c
            Build depl               -> Ops.build                     o c depl
            AMI                      -> Cardano.buildAMI              o c
            -- * deployment lifecycle
            Nixops' cmd args         -> Ops.nixops                    o c cmd args
            Create                   -> Ops.create                    o c
            Modify                   -> Ops.modify                    o c
            Deploy ner bu dry ch buh -> Ops.deploy                    o c dry bu ch ner buh
            Destroy                  -> Ops.destroy                   o c
            Delete                   -> Ops.delete                    o c
            Info                     -> Ops.nixops                    o c "info" []
            -- * High-level scenarios
            DeployFull              br st genes preGen wipeDB noExRe skipV resume -> Ops.deployFull              o c br st genes preGen wipeDB noExRe skipV resume
            DeployFullDeployerPhase    st              wipeDB noExRe              -> Ops.deployFullDeployerPhase o c    st              wipeDB noExRe
            FromScratch              -> Ops.fromscratch               o c
            ReallocateCoreIPs        -> Ops.reallocateCoreIPs         o c
            -- * live deployment ops
            DeployedCommit m         -> Ops.deployedCommit            o c m
            CheckStatus              -> Ops.checkstatus               o c
            StartForeground          -> Ops.startForeground           o c $
                                        flip fromMaybe oOnlyOn $ error "'start-foreground' requires a global value for --on/-o"
            Ssh exec args            -> Ops.parallelSSH               o c exec args
            Stop                     -> Ops.stop                      o c
            RunExperiment Nodes      -> Cardano.runexperiment     o c
            RunExperiment x          -> die $ "RunExperiment undefined for deployment " <> showT x
            PostExperiment           -> Cardano.postexperiment        o c
            DumpLogs{..}
              | Nodes        <- depl -> Cardano.dumpLogs              o c withProf >> pure ()
              | x            <- depl -> die $ "DumpLogs undefined for deployment " <> showT x
            CWipeJournals            -> Ops.wipeJournals              o c
            GetJournals              -> Ops.getJournals               o c
            CWipeNodeDBs confirm     -> Ops.wipeNodeDBs               o c confirm
            PrintDate                -> Ops.date                      o c
            Clone{..}                -> error "impossible"
            Template{..}             -> error "impossible"
            SetRev   _ _ _           -> error "impossible"


runClone :: Options -> Branch -> IO ()
runClone o@Options{..} branch = do
  let bname     = fromBranch branch
      branchDir = fromText bname
  exists <- testpath branchDir
  if exists
  then  echo $ "Using existing git clone ..."
  else cmd o "git" ["clone", Ops.fromURL $ Ops.projectURL IOHKOps, "-b", bname, bname]

  cd branchDir
  cmd o "git" (["config", "--replace-all", "receive.denyCurrentBranch", "updateInstead"])

runTemplate :: Options -> Command -> [Arg] -> IO ()
runTemplate o@Options{..} Template{..} args = do
  when (elem (fromNixopsDepl tName) $ showT <$> (every :: [Deployment])) $
    die $ format ("the deployment name "%w%" ambiguously refers to a deployment _type_.  Cannot have that!") (fromNixopsDepl tName)

  systemStart <- timeCurrent
  let cmdline = T.concat $ intersperse " " $ fromArg <$> args
  nixops <- (<> "/bin/nixops") . T.strip <$> incmd o "nix-build" ["-A", "nixops"]
  config <- Ops.mkNewConfig o cmdline tName (tNixops <|> (Path.fromText <$> Just nixops)) tGenesis tTopology tEnvironment tTarget tDeployments systemStart tConfigurationKey
  configFilename <- T.pack . Path.encodeString <$> Ops.writeConfig tFile config

  echo ""
  echo $ "-- " <> (unsafeTextToLine $ configFilename) <> " is:"
  cmd o "cat" [configFilename]
runTemplate _ _ _ = error "impossible"
