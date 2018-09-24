#!/usr/bin/env runhaskell
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RecordWildCards    #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TupleSections      #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults #-}

module Main where

import           Control.Monad             (forM_)
import           Data.Char                 (toLower)
import           Data.List
import qualified Data.Map                  as Map
import           Data.Maybe
import           Data.Monoid               ((<>))
import           Data.Optional             (Optional)
import qualified Data.Text                 as T
import qualified Filesystem.Path.CurrentOS as Path
import           Options.Applicative       (auto, long, metavar, option, short,
                                            str)
import           Prelude                   hiding (FilePath)
import qualified System.Environment        as Sys
import           Time.System
import           Time.Types
import           Turtle                    hiding (e, env, err, f, fold, inproc,
                                            o, option, procs, shells, x)

import           Constants
import           NixOps
import qualified NixOps                    as Ops
import           Types
import           UpdateProposal
import           Utils


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
  Clone                 :: { cName        :: NixopsDepl
                           , cBranch      :: Branch
                           } -> Command
  New                   :: { tFile        :: Maybe Turtle.FilePath
                           , tTopology    :: Maybe Turtle.FilePath
                           , tConfigurationKey :: Maybe ConfigurationKey
                           , tGenerateKeys :: GenerateKeys
                           , tEnvironment :: Environment
                           , tTarget      :: Target
                           , tName        :: NixopsDepl
                           , tDeployments :: [Deployment]
                           } -> Command
  SetRev                :: Project -> Commit -> DoCommit -> Command

  -- * building
  Build                 :: Deployment -> Command
  AMI                   :: Command

  -- * cluster lifecycle
  Nixops'               :: NixopsCmd -> [Arg] -> Command
  Modify                :: Command
  Deploy                :: BuildOnly -> DryRun -> PassCheck -> Maybe Seconds -> Command
  Destroy               :: Command
  Delete                :: Command
  Info                  :: Command

  -- * high-level scenarios
  FromScratch           :: Command
  ReallocateCoreIPs     :: Command

  -- * live cluster ops
  Ssh                   :: Exec -> [Arg] -> Command
  DeployedCommit        :: NodeName -> Command
  CheckStatus           :: Command
  StartForeground       :: Command
  Stop                  :: Command
  DumpLogs              :: { depl :: Deployment, withProf :: Bool } -> Command
  CWipeJournals         :: Command
  GetJournals           :: JournaldTimeSpec -> Maybe JournaldTimeSpec -> Command
  CWipeNodeDBs          :: Confirmation -> Command
  PrintDate             :: Command
  FindInstallers        :: Text -> Maybe FilePath -> Maybe Int -> Maybe Int -> Command
  UpdateProposal        :: UpdateProposalCommand -> Command
deriving instance Show Command

centralCommandParser :: Parser Command
centralCommandParser =
  (    subcommandGroup "General:"
    [ ("clone",                 "Clone an 'iohk-ops' repository branch",
                                Clone
                                <$> (NixopsDepl <$> argText "NAME"  "Nixops deployment name")
                                <*> (fromMaybe defaultIOPSBranch
                                     <$> (optional (parserBranch "'iohk-ops' branch to checkout.  Defaults to 'master'"))))
    , ("new",                   "Produce (or update) a checkout of BRANCH with a cluster config YAML file (whose default name depends on the ENVIRONMENT), primed for future operations.",
                                New
                                <$> optional (optPath "config"        'c' "Override the default, environment-dependent config filename")
                                <*> optional (optPath "topology"      't' "Cluster configuration.  Defaults to 'topology.yaml'")
                                <*> optional parserConfigurationKey
                                <*> flag DontGenerateKeys "dont-generate-keys" 'd' "Don't generate development keys"
                                <*> parserEnvironment
                                <*> parserTarget
                                <*> (NixopsDepl <$> argText "NAME"  "Nixops deployment name")
                                <*> parserDeployments)
    , ("set-rev",               "Set commit of PROJECT dependency to COMMIT, and commit the resulting changes",
                                SetRev
                                <$> parserProject
                                <*> parserCommit "Commit to set PROJECT's version to"
                                <*> flag DontCommit "dont-commit" 'n' "Don't commit the *-src.json")
    ]

   <|> subcommandGroup "Build-related:"
    [ ("build",                 "Build the application specified by DEPLOYMENT",                    Build <$> parserDeployment)
    , ("ami",                   "Build ami",                                                        pure AMI) ]

   -- * cluster lifecycle

   <|> subcommandGroup "Cluster lifecycle:"
   [
     -- ("nixops",                "Call 'nixops' with current configuration",
     --                           (Nixops
     --                            <$> (NixopsCmd <$> argText "CMD" "Nixops command to invoke")
     --                            <*> ???)) -- should we switch to optparse-applicative?
     ("modify",                 "Update cluster state with the nix expression changes",             pure Modify)
   , ("create",                 "Same as modify",                                                   pure Modify)
   , ("deploy",                 "Deploy the whole cluster",
                                Deploy
                                <$> flag BuildOnly         "build-only"          'b' "Pass --build-only to 'nixops deploy'"
                                <*> flag DryRun            "dry-run"             'd' "Pass --dry-run to 'nixops deploy'"
                                <*> flag PassCheck         "check"               'c' "Pass --check to 'nixops build'"
                                <*> ((Seconds . (* 60) . fromIntegral <$>)
                                      <$> optional (optInteger "bump-system-start-held-by" 't' "Bump cluster --system-start time, and add this many minutes to delay")))
   , ("destroy",                "Destroy the whole cluster",                                        pure Destroy)
   , ("delete",                 "Unregistr the cluster from NixOps",                                pure Delete)
   , ("fromscratch",            "Destroy, Delete, Create, Deploy",                                  pure FromScratch)
   , ("reallocate-core-ips",    "Destroy elastic IPs corresponding to the nodes listed and redeploy cluster",
                                                                                                    pure ReallocateCoreIPs)
   , ("info",                   "Invoke 'nixops info'",                                             pure Info)]

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
   , ("dumplogs",               "Dump logs",
                                DumpLogs
                                <$> parserDeployment
                                <*> switch "prof"         'p' "Dump profiling data as well (requires service stop)")
   , ("wipe-journals",          "Wipe *all* journald logs on cluster",                              pure CWipeJournals)
   , ("get-journals",           "Obtain cardano-node journald logs from cluster",
                                GetJournals
                                <$> ((fromMaybe Constants.defaultJournaldTimeSpec . (Types.JournaldTimeSpec <$>))
                                      <$> optional (optText "since" 's' "Get logs since this journald time spec.  Defaults to '6 hours ago'"))
                                <*> ((Types.JournaldTimeSpec <$>) <$>
                                     optional (optText "until" 'u' "Get logs until this journald time spec.  Defaults to 'now'")))
   , ("wipe-node-dbs",          "Wipe *all* node databases on cluster (--on limits the scope, though)",
                                CWipeNodeDBs
                                <$> parserConfirmation "Wipe node DBs on the entire cluster?")
   , ("date",                   "Print date/time",                                                  pure PrintDate)
   , ("update-proposal",        "Subcommands for updating wallet installers. Apply commands in the order listed.", UpdateProposal <$> parseUpdateProposalCommand)
   , ("find-installers",        "find installers from CI",                                          FindInstallers <$> (option str (long "daedalus-rev" <> short 'r' <> metavar "SHA1")) <*> optional (optPath "download" 'd' "Download the found installers to the given directory.") <*> optional (option auto (long "buildkite-build-num"  <> metavar "NUMBER")) <*> optional (option auto (long "appveyor-build-num" <> metavar "NUMBER")))
   ]

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
    Clone{..}                   -> runClone           o cName cBranch
    New{..}                     -> runNew             o topcmd  args
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
            -- * building
            Build depl               -> Ops.build                     o c depl
            AMI                      -> Ops.buildAMI              o c
            -- * deployment lifecycle
            Nixops' cmd args         -> Ops.nixops                    o c cmd args
            Modify                   -> Ops.modify                    o c
            Deploy bu dry ch buh     -> Ops.deploy                    o c dry bu ch buh
            Destroy                  -> Ops.destroy                   o c
            Delete                   -> Ops.delete                    o c
            Info                     -> Ops.nixops                    o c "info" []
            -- * High-level scenarios
            FromScratch              -> Ops.fromscratch               o c
            ReallocateCoreIPs        -> Ops.reallocateCoreIPs         o c
            -- * live deployment ops
            DeployedCommit m         -> Ops.deployedCommit            o c m
            CheckStatus              -> Ops.checkstatus               o c
            StartForeground          -> Ops.startForeground           o c $
                                        flip fromMaybe oOnlyOn $ error "'start-foreground' requires a global value for --on/-o"
            Ssh exec args            -> Ops.parallelSSH               o c exec args
            Stop                     -> Ops.stop                      o c
            DumpLogs{..}
              | Nodes        <- depl -> Ops.dumpLogs              o c withProf >> pure ()
              | x            <- depl -> die $ "DumpLogs undefined for deployment " <> showT x
            CWipeJournals            -> Ops.wipeJournals              o c
            GetJournals since until  -> Ops.getJournals               o c since until
            CWipeNodeDBs confirm     -> Ops.wipeNodeDBs               o c confirm
            PrintDate                -> Ops.date                      o c
            FindInstallers rev dl bk av -> Ops.findInstallers         c rev dl bk av
            UpdateProposal up        -> updateProposal                o c up
            Clone{..}                -> error "impossible"
            New{..}                  -> error "impossible"
            SetRev   _ _ _           -> error "impossible"


runClone :: Options -> NixopsDepl -> Branch -> IO ()
runClone o@Options{..} depl branch = do
  let bname     = fromBranch branch
      branchDir = fromText $ fromNixopsDepl depl
  exists <- testpath branchDir
  if exists
  then  echo $ "Using existing git clone ..."
  else cmd o "git" ["clone", Ops.fromURL $ Ops.projectURL IOHKOps, "-b", bname, fromNixopsDepl depl]

  cd branchDir
  cmd o "git" (["config", "--replace-all", "receive.denyCurrentBranch", "updateInstead"])

runNew :: Options -> Command -> [Arg] -> IO ()
runNew o@Options{..} New{..} args = do
  when (elem (fromNixopsDepl tName) $ let names = showT <$> (every :: [Deployment])
                                      in names <> (T.toLower <$> names)) $
    die $ format ("the deployment name "%w%" ambiguously refers to a deployment _type_.  Cannot have that!") (fromNixopsDepl tName)

  -- generate config:
  systemStart <- timeCurrent
  let cmdline = T.concat $ intersperse " " $ fromArg <$> args
  config <- Ops.mkNewConfig o cmdline tName tTopology tEnvironment tTarget tDeployments systemStart tConfigurationKey
  configFilename <- T.pack . Path.encodeString <$> Ops.writeConfig tFile config

  echo ""
  echo $ "-- " <> (unsafeTextToLine $ configFilename) <> " is:"
  cmd o "cat" [configFilename]

  -- generate dev-keys & ensure secrets exist:
  when (tEnvironment == Development || tEnvironment == Benchmark) $ do
    let secrets = [ "static/github_token"
                  , "static/id_buildfarm"
                  , "static/datadog-api.secret"
                  , "static/google_oauth_hydra_grafana.secret"
                  , "static/github-webhook-util.secret"
                  , "static/datadog-application.secret"
                  , "static/zendesk-token.secret" ]
    forM_ secrets touch
    echo "Ensured secrets exist"

    if (tGenerateKeys /= GenerateKeys)
    then echo "Skipping key generation, due to user request"
    else do
      generateStakeKeys o (clusterConfigurationKey config) "keys"
      sh $ do
        k <- Turtle.find ((prefix "keys/generated-keys/rich/key") <> (suffix ".sk"))
          "keys/generated-keys/rich"
        cp k $ "keys" </> Path.filename k
  echo "Cluster deployment has been prepared."

runNew _ _ _ = error "impossible"

-- | Use 'cardano-keygen' to create keys for a develoment cluster.
generateStakeKeys :: Options -> ConfigurationKey -> Turtle.FilePath -> IO ()
generateStakeKeys o configurationKey outdir = do
  cardanoConfig <- getCardanoSLConfig o
  cmd o "cardano-keygen"
    [ "--system-start", "0"
    , "--configuration-file", format (fp%"/lib/configuration.yaml") cardanoConfig
    , "--configuration-key", fromConfigurationKey configurationKey
    , "generate-keys-by-spec"
    , "--genesis-out-dir", T.pack $ Path.encodeString outdir
    ]
