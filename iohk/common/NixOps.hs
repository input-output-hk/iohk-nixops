{-# OPTIONS_GHC -Wall -Wextra -Wno-orphans -Wno-missing-signatures -Wno-unticked-promoted-constructors -Wno-type-defaults #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ViewPatterns #-}

module NixOps (
    nixops
  , modify
  , deploy
  , destroy
  , delete

  , build
  , buildAMI
  , stop
  , start
  , fromscratch
  , dumpLogs
  , getJournals
  , wipeJournals
  , wipeNodeDBs
  , startForeground

  , runSetRev
  , reallocateCoreIPs
  , deployedCommit
  , checkstatus
  , parallelSSH
  , NixOps.date
  , findInstallers

  , awsPublicIPURL
  , defaultEnvironment
  , defaultNode
  , defaultNodePort
  , defaultTarget

  , cmd, cmd', incmd, incmdStrip
  , errorT
  , every
  , jsonLowerStrip
  , lowerShowT
  , parallelIO
  , nixopsConfigurationKey
  , configurationKeys
  , getCardanoSLConfig

  -- * Types
  , Arg(..)
  , Branch(..)
  , Commit(..)
  , ConfigurationKey(..)
  , Confirmation(..)
  , Deployment(..)
  , EnvVar(..)
  , Environment(..)
  , envDefaultConfig
  , envSettings
  , Exec(..)
  , NixopsCmd(..)
  , NixopsConfig(..)
  , clusterConfigurationKey
  , NixopsDepl(..)
  , NixSource(..)
  , githubSource, gitSource, readSource
  , NodeName(..)
  , fromNodeName
  , Options(..)
  , Org(..)
  , PortNo(..)
  , Project(..)
  , projectURL
  , Region(..)
  , Target(..)
  , URL(..)
  , Username(..)
  , Zone(..)

  -- * Flags
  , BuildOnly(..)
  , DoCommit(..)
  , DryRun(..)
  , PassCheck(..)
  , enabled
  , disabled
  , opposite
  , toBool

  --
  , parserBranch
  , parserCommit
  , parserNodeLimit
  , parserOptions

  , mkNewConfig
  , readConfig
  , writeConfig

  -- * Legacy
  , DeploymentInfo(..)
  , getNodePublicIP
  , getIP
  , defLogs, profLogs
  , info
  , scpFromNode
  , toNodesInfo
  )
where

import           Control.Arrow                   ((***))
import           Control.Exception                (throwIO)
import           Control.Lens                     ((<&>))
import           Control.Monad                    (forM_, mapM_)
import qualified Data.Aeson                    as AE
import           Data.Aeson                       ((.:), (.:?), (.=), (.!=))
import           Data.Aeson.Encode.Pretty         (encodePretty)
import qualified Data.ByteString.UTF8          as BU
import qualified Data.ByteString.Lazy.UTF8     as LBU
import           Data.Char                        (ord)
import           Data.Csv                         (decodeWith, FromRecord(..), FromField(..), HasHeader(..), defaultDecodeOptions, decDelimiter)
import           Data.Either
import           Data.Hourglass                   (timeAdd, timeFromElapsed, timePrint, Duration(..), ISO8601_DateAndTime(..))
import           Data.List                        (nub, sort)
import           Data.Maybe
import qualified Data.Map.Strict               as Map
import           Data.Monoid                      ((<>))
import           Data.Optional                    (Optional)
import qualified Data.Set                      as Set
import qualified Data.Text                     as T
import qualified Data.Text.IO                  as TIO
import           Data.Text.Lazy                   (fromStrict)
import           Data.Text.Lazy.Encoding          (encodeUtf8)
import qualified Data.Vector                   as V
import qualified Data.Yaml                     as YAML
import           Data.Yaml                        (FromJSON(..), ToJSON(..))
import           Debug.Trace                      (trace)
import qualified Filesystem.Path.CurrentOS     as Path
import           GHC.Generics              hiding (from, to)
import           Options.Applicative              (flag)
import           Prelude                   hiding (FilePath)
import           Safe                             (headMay)
import qualified System.IO                     as Sys
import qualified System.IO.Unsafe              as Sys
import           Time.System
import           Time.Types
import           Turtle                    hiding (env, err, fold, inproc, prefix, procs, e, f, o, x, view, toText, within, sort, nub)
import qualified Turtle                        as Turtle

import           Network.AWS.S3.Types      hiding (All, URL, Region)
import           UpdateLogic

import           Constants
import           Nix
import           Topology
import           Types
import           Utils
import           GHC.Stack                 (HasCallStack)


-- * Some orphan instances..
--
deriving instance Generic Seconds; instance FromJSON Seconds; instance ToJSON Seconds
deriving instance Generic Elapsed; instance FromJSON Elapsed; instance ToJSON Elapsed
instance ToJSON SimpleTopo


establishDeployerIP :: Options -> Maybe IP -> IO IP
establishDeployerIP o Nothing   = IP <$> incmdStrip o "curl" opts
  where opts = ["--connect-timeout", "2", "--silent", fromURL awsPublicIPURL]
establishDeployerIP _ (Just ip) = pure ip


-- * Deployment file set computation
--
filespecDeplSpecific :: Deployment -> FileSpec -> Bool
filespecDeplSpecific x (x', _, _) = x == x'
filespecTgtSpecific  :: Target     -> FileSpec -> Bool
filespecTgtSpecific  x (_, x', _) = x == x'

filespecNeededDepl   :: Deployment -> FileSpec -> Bool
filespecNeededTgt    :: Target     -> FileSpec -> Bool
filespecNeededDepl x fs = filespecDeplSpecific Every fs || filespecDeplSpecific x fs
filespecNeededTgt  x fs = filespecTgtSpecific  All   fs || filespecTgtSpecific  x fs

filespecFile :: FileSpec -> Text
filespecFile (_, _, x) = x

elementDeploymentFiles :: Environment -> Target -> Deployment -> [Text]
elementDeploymentFiles env tgt depl = filespecFile <$> (filter (\x -> filespecNeededDepl depl x && filespecNeededTgt tgt x) $ envDeploymentFiles $ envSettings env)


-- * Topology
--
-- Design:
--  1. we have the full Topology, and its SimpleTopo subset, which is converted to JSON for Nix's consumption.
--  2. the SimpleTopo is only really needed when we have Nodes to deploy
--  3. 'getSimpleTopo' is what executes the decision in #2
--
readTopology :: FilePath -> IO Topology
readTopology file = do
  eTopo <- liftIO $ YAML.decodeFileEither $ Path.encodeString file
  case eTopo of
    Right (topology :: Topology) -> pure topology
    Left err -> errorT $ format ("Failed to parse topology file: "%fp%": "%w) file err

instance ToJSON SimpleNode where
  toJSON SimpleNode{..} = AE.object
   [ "type"        .= (lowerShowT snType & T.stripPrefix "node"
                        & fromMaybe (error "A NodeType constructor gone mad: doesn't start with 'Node'."))
   , "region"      .= snRegion
   , "zone"        .= snZone
   , "org"         .= snOrg
   , "address"     .= fromFQDN snFQDN
   , "port"        .= fromPortNo snPort
   , "peers"       .= snInPeers
   , "kademlia"    .= snKademlia
   , "public"      .= snPublic ]

instance ToJSON NodeRegion
instance ToJSON NodeName
deriving instance Generic NodeName
deriving instance Generic NodeRegion
deriving instance Generic NodeType
instance ToJSON NodeType

topoNodes :: SimpleTopo -> [NodeName]
topoNodes (SimpleTopo cmap) = Map.keys cmap

topoCores :: SimpleTopo -> [NodeName]
topoCores = (fst <$>) . filter ((== NodeCore) . snType . snd) . Map.toList . fromSimpleTopo

stubTopology :: SimpleTopo
stubTopology = SimpleTopo Map.empty

summariseTopology :: Topology -> SimpleTopo
summariseTopology (TopologyStatic (AllStaticallyKnownPeers nodeMap)) =
  SimpleTopo $ Map.mapWithKey simplifier nodeMap
  where simplifier node (NodeMetadata snType snRegion (NodeRoutes outRoutes) nmAddr snKademlia snPublic mbOrg snZone) =
          SimpleNode{..}
          where (mPort,  fqdn)   = case nmAddr of
                                     (NodeAddrExact fqdn'  mPort') -> (mPort', fqdn') -- (Ok, bizarrely, this contains FQDNs, even if, well.. : -)
                                     (NodeAddrDNS   mFqdn  mPort') -> (mPort', flip fromMaybe mFqdn
                                                                      $ error "Cannot deploy a topology with nodes lacking a FQDN address.")
                (snPort, snFQDN) = (,) (fromMaybe defaultNodePort $ PortNo . fromIntegral <$> mPort)
                                   $ (FQDN . T.pack . BU.toString) $ fqdn
                snInPeers = Set.toList . Set.fromList
                            $ [ other
                              | (other, (NodeMetadata _ _ (NodeRoutes routes) _ _ _ _ _)) <- Map.toList nodeMap
                              , elem node (concat routes) ]
                            <> concat outRoutes
                snOrg = fromMaybe (trace (T.unpack $ format ("WARNING: node '"%s%"' has no 'org' field specified, defaulting to "%w%".")
                                          (fromNodeName node) defaultOrg)
                                   defaultOrg)
                        mbOrg
summariseTopology x = errorT $ format ("Unsupported topology type: "%w) x

getSimpleTopo :: [Deployment] -> FilePath -> IO SimpleTopo
getSimpleTopo cElements cTopology =
  if not $ elem Nodes cElements then pure stubTopology
  else do
    topoExists <- testpath cTopology
    unless topoExists $
      die $ format ("Topology config '"%fp%"' doesn't exist.") cTopology
    summariseTopology <$> readTopology cTopology

-- | Dump intermediate core/relay info, as parametrised by the simplified topology file.
dumpTopologyNix :: NixopsConfig -> IO ()
dumpTopologyNix NixopsConfig{..} = sh $ do
  let nodeSpecExpr prefix =
        format ("with (import <nixpkgs> {}); "%s%" (import ./globals.nix { deployerIP = \"\"; environment = \""%s%"\"; topologyYaml = ./"%fp%"; systemStart = 0; "%s%" = \"-stub-\"; })")
               prefix (lowerShowT cEnvironment) cTopology (T.intercalate " = \"-stub-\"; " $ fromAccessKeyId <$> accessKeyChain)
      getNodeArgsAttr prefix attr = inproc "nix-instantiate" ["--strict", "--show-trace", "--eval" ,"-E", nodeSpecExpr prefix <> "." <> attr] empty
      liftNixList = inproc "sed" ["s/\" \"/\", \"/g"]
  (cores  :: [NodeName]) <- getNodeArgsAttr "map (x: x.name)" "cores"  & liftNixList <&> ((NodeName <$>) . readT . lineToText)
  (relays :: [NodeName]) <- getNodeArgsAttr "map (x: x.name)" "relays" & liftNixList <&> ((NodeName <$>) . readT . lineToText)
  echo "Cores:"
  forM_ cores  $ \(NodeName x) -> do
    printf ("  "%s%"\n    ") x
    Turtle.proc "nix-instantiate" ["--strict", "--show-trace", "--eval" ,"-E", nodeSpecExpr "" <> ".nodeMap." <> x] empty
  echo "Relays:"
  forM_ relays $ \(NodeName x) -> do
    printf ("  "%s%"\n    ") x
    Turtle.proc "nix-instantiate" ["--strict", "--show-trace", "--eval" ,"-E", nodeSpecExpr "" <> ".nodeMap." <> x] empty

nodeNames :: Options -> NixopsConfig -> [NodeName]
nodeNames (oOnlyOn -> nodeLimit)  NixopsConfig{..}
  | Nothing   <- nodeLimit = topoNodes topology <> [explorerNode | elem Explorer cElements]
  | Just node <- nodeLimit
  , SimpleTopo nodeMap <- topology
  = if Map.member node nodeMap || node == explorerNode then [node]
    else errorT $ format ("Node '"%s%"' doesn't exist in cluster '"%fp%"'.") (showT $ fromNodeName node) cTopology

scopeNameDesc :: Options -> NixopsConfig -> (Text, Text)
scopeNameDesc (oOnlyOn -> nodeLimit)  NixopsConfig{..}
  | Nothing   <- nodeLimit = (format ("entire '"%s%"' cluster") (fromNixopsDepl cName)
                             ,"cluster-" <> fromNixopsDepl cName)
  | Just node <- nodeLimit = (format ("node '"%s%"'") (fromNodeName node)
                             ,"node-" <> fromNodeName node)



data Options = Options
  { oChdir            :: Maybe FilePath
  , oConfigFile       :: Maybe FilePath
  , oOnlyOn           :: Maybe NodeName
  , oDeployerIP       :: Maybe IP
  , oConfirm          :: Confirmed
  , oDebug            :: Debug
  , oSerial           :: Serialize
  , oVerbose          :: Verbose
  , oNoComponentCheck :: ComponentCheck
  , oInitialHeapSize  :: Maybe Int
  } deriving Show

parserBranch :: Optional HelpMessage -> Parser Branch
parserBranch desc = Branch <$> argText "branch" desc

parserCommit :: Optional HelpMessage -> Parser Commit
parserCommit desc = Commit <$> argText "commit" desc

parserNodeLimit :: Parser (Maybe NodeName)
parserNodeLimit = optional $ NodeName <$> (optText "just-node" 'n' "Limit operation to the specified node")

parserOptions :: Parser Options
parserOptions = Options
                <$> optional (optPath "chdir"     'C' "Run as if 'iohk-ops' was started in <path> instead of the current working directory.")
                <*> optional (optPath "config"    'c' "Configuration file")
                <*> (optional $ NodeName
                     <$>     (optText "on"        'o' "Limit operation to the specified node"))
                <*> (optional $ IP
                     <$>     (optText "deployer"  'd' "Directly specify IP address of the deployer: do not detect"))
                <*> flag UnConfirmed Confirmed (long "confirm" <> short 'y' <> help "Pass --confirm to nixops")
                <*> flag NoDebug Debug (long "debug" <> short 'd' <> help "Pass --debug to nixops")
                <*> flag DontSerialize Serialize (long "serial" <> short 's' <> help "Disable parallelisation")
                <*> flag NotVerbose Verbose (long "verbose" <> short 'v' <> help "Print all commands that are being run")
                <*> flag ComponentCheck NoComponentCheck (long "no-component-check" <> short 'p' <> help "Disable deployment/*.nix component check")
                <*> initialHeapSizeFlag

-- Nix initial heap size -- default 12GiB, specify 0 to disable.
-- For 100 nodes it eats 12GB of ram *and* needs a bigger heap.
initialHeapSizeFlag :: Parser (Maybe Int)
initialHeapSizeFlag = interpret <$> optional o
  where
    o = optInt "initial-heap-size" 'G' "Initial heap size for Nix (GiB), default 12"
    interpret (Just n) | n > 0 = Just (gb n)
                       | otherwise = Nothing
    interpret Nothing = Just (gb 12)
    gb n = n * 1024 * 1024 * 1024

nixopsCmdOptions :: Options -> NixopsConfig -> [Text]
nixopsCmdOptions Options{..} NixopsConfig{..} =
  ["--debug"   | oDebug   == Debug]   <>
  ["--confirm" | oConfirm == Confirmed] <>
  ["--show-trace"
  ,"--deployment", fromNixopsDepl cName
  ] <> (["-I", format ("nixpkgs="%fp) nixpkgs])


instance ToJSON BucketName
instance FromJSON NixopsConfig where
    parseJSON = AE.withObject "NixopsConfig" $ \v -> NixopsConfig
        <$> v .: "name"
        <*> v .:? "gen-cmdline"   .!= "--unknown--"
        <*> v .:? "topology"      .!= "topology-development.yaml"
        <*> v .: "environment"
        <*> v .: "target"
        <*> v .: "installer-bucket"
        <*> v .: "installer-url-base"
        <*> v .: "elements"
        <*> v .: "files"
        <*> v .: "args"
        -- Filled in in readConfig:
        <*> pure undefined
        <*> pure undefined

instance FromJSON BucketName
instance ToJSON Environment
instance ToJSON Target
instance ToJSON Deployment
instance ToJSON NixopsConfig where
  toJSON NixopsConfig{..} = AE.object
   [ "name"               .= fromNixopsDepl cName
   , "gen-cmdline"        .= cGenCmdline
   , "topology"           .= cTopology
   , "environment"        .= showT cEnvironment
   , "target"             .= showT cTarget
   , "installer-bucket"   .= cUpdateBucket
   , "installer-url-base" .= cInstallerURLBase
   , "elements"           .= cElements
   , "files"              .= cFiles
   , "args"               .= cDeplArgs ]

deploymentFiles :: Environment -> Target -> [Deployment] -> [Text]
deploymentFiles cEnvironment cTarget cElements =
  nub $ concat (elementDeploymentFiles cEnvironment cTarget <$> cElements)

selectInitialConfigDeploymentArgs :: Options -> FilePath -> Environment -> [Deployment] -> Elapsed -> Maybe ConfigurationKey -> IO DeplArgs
selectInitialConfigDeploymentArgs _ _ env delts (Elapsed systemStart) mConfigurationKey = do
    let EnvSettings{..}   = envSettings env
        akidDependentArgs = [ ( NixParam $ fromAccessKeyId akid
                              , NixStr . fromNodeName $ selectDeployer env delts)
                            | akid <- accessKeyChain ]
        configurationKey  = fromMaybe envDefaultConfigurationKey mConfigurationKey
    pure $ Map.fromList $
      akidDependentArgs
      <> [ ("systemStart",  NixInt $ fromIntegral systemStart)
         , ("configurationKey", NixStr $ fromConfigurationKey configurationKey)
         ]

deplArg :: NixopsConfig -> NixParam -> NixValue -> NixValue
deplArg    NixopsConfig{..} k def = Map.lookup k cDeplArgs & fromMaybe def
  --(errorT $ format ("Deployment arguments don't hold a value for key '"%s%"'.") (showT k))

setDeplArg :: NixParam -> NixValue -> NixopsConfig -> NixopsConfig
setDeplArg p v c@NixopsConfig{..} = c { cDeplArgs = Map.insert p v cDeplArgs }

-- | Gets the "configurationKey" string out of the NixOps deployment args
nixopsConfigurationKey :: NixopsConfig -> Maybe Text
nixopsConfigurationKey = (>>= asString) . Map.lookup "configurationKey" . cDeplArgs
  where
    -- maybe generating prisms on NixValue would be better.
    -- or maybe using hnix instead of Nix.hs and generating prisms
    asString (NixStr s) = Just s
    asString _ = Nothing

-- | Interpret inputs into a NixopsConfig
mkNewConfig :: Options -> Text -> NixopsDepl -> Maybe FilePath -> Environment -> Target -> [Deployment] -> Elapsed -> Maybe ConfigurationKey -> IO NixopsConfig
mkNewConfig o cGenCmdline cName                       mTopology cEnvironment cTarget cElements systemStart mConfigurationKey = do
  let EnvSettings{..} = envSettings                             cEnvironment
      cFiles          = deploymentFiles                         cEnvironment cTarget cElements
      cTopology       = flip fromMaybe                mTopology envDefaultTopology
      cUpdateBucket   = "default-bucket"
      cInstallerURLBase = Nothing
  cDeplArgs <- selectInitialConfigDeploymentArgs o cTopology cEnvironment         cElements systemStart mConfigurationKey
  topology  <- getSimpleTopo cElements cTopology
  nixpkgs   <- Path.fromText <$> incmdStrip o "nix-build" ["--no-out-link", "fetch-nixpkgs.nix"]
  pure NixopsConfig{..}

-- | Write the config file
writeConfig :: MonadIO m => Maybe FilePath -> NixopsConfig -> m FilePath
writeConfig mFp c@NixopsConfig{..} = do
  let configFilename = flip fromMaybe mFp $ envDefaultConfig $ envSettings cEnvironment
  liftIO $ writeTextFile configFilename $ T.pack $ BU.toString $ YAML.encode c
  pure configFilename

-- | Read back config, doing validation
readConfig :: (HasCallStack, MonadIO m) => Options -> FilePath -> m NixopsConfig
readConfig o@Options{..} cf = do
  cfParse <- liftIO $ YAML.decodeFileEither $ Path.encodeString $ cf
  let c@NixopsConfig{..}
        = case cfParse of
            Right cfg -> cfg
            -- TODO: catch and suggest versioning
            Left  e -> errorT $ format ("Failed to parse config file "%fp%": "%s)
                       cf (T.pack $ YAML.prettyPrintParseException e)
      storedFileSet  = Set.fromList cFiles
      deducedFiles   = deploymentFiles cEnvironment cTarget cElements
      deducedFileSet = Set.fromList $ deducedFiles

  unless (storedFileSet == deducedFileSet || oNoComponentCheck == NoComponentCheck) $
    die $ format ("Config file '"%fp%"' is incoherent with respect to elements "%w%":\n  - stored files:  "%w%"\n  - implied files: "%w%"\n")
          cf cElements (sort cFiles) (sort deducedFiles)
  -- Can't read topology file without knowing its name, hence this phasing.
  topo <- liftIO $ getSimpleTopo cElements cTopology
  nixpkgs' <- Path.fromText <$> (liftIO $ incmdStrip o "nix-build" ["--no-out-link", "fetch-nixpkgs.nix"])
  pure c { topology = topo, nixpkgs = nixpkgs' }

clusterConfigurationKey :: NixopsConfig -> ConfigurationKey
clusterConfigurationKey c =
  ConfigurationKey . fromNixStr $ deplArg c (NixParam "configurationKey") $ errorT $
                                  format "'configurationKey' network argument missing from cluster config"


parallelIO' :: Options -> NixopsConfig -> ([NodeName] -> [a]) -> (a -> IO ()) -> IO ()
parallelIO' o@Options{..} c@NixopsConfig{..} xform action =
  ((case oSerial of
      Serialize     -> sequence_
      DontSerialize -> sh . parallel) $
   action <$> (xform $ nodeNames o c))
  >> echo ""

parallelIO :: Options -> NixopsConfig -> (NodeName -> IO ()) -> IO ()
parallelIO o c = parallelIO' o c id

logCmd  bin args = do
  printf ("-- "%s%"\n") $ T.intercalate " " $ bin:args
  Sys.hFlush Sys.stdout

inproc :: Text -> [Text] -> Shell Line -> Shell Line
inproc bin args inp = do
  liftIO $ logCmd bin args
  Turtle.inproc bin args inp

minprocs :: MonadIO m => Text -> [Text] -> Shell Line -> m (Either ProcFailed Text)
minprocs bin args inp = do
  (exitCode, out) <- liftIO $ procStrict bin args inp
  pure $ case exitCode of
           ExitSuccess -> Right out
           _           -> Left $ ProcFailed bin args exitCode

inprocs :: MonadIO m => Text -> [Text] -> Shell Line -> m Text
inprocs bin args inp = do
  ret <- minprocs bin args inp
  case ret of
    Right out -> pure out
    Left  err -> liftIO $ throwIO err

cmd   :: Options -> Text -> [Text] -> IO ()
cmd'  :: Options -> Text -> [Text] -> IO (ExitCode, Text)
cmd'' :: Options -> Text           -> IO (ExitCode, Text, Text)
incmd, incmdStrip :: Options -> Text -> [Text] -> IO Text

cmd   Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  Turtle.procs      bin args empty
cmd'  Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  Turtle.procStrict bin args empty
cmd'' Options{..} command  = do
  when (toBool oVerbose) $ logCmd command []
  Turtle.shellStrictWithErr command empty
incmd Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  inprocs bin args empty
incmdStrip Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  T.strip <$> inprocs bin args empty


-- * Invoking nixops
--
iohkNixopsPath :: FilePath
iohkNixopsPath =
  let defaultNix = "default.nix"
      storePath  = Sys.unsafePerformIO $ inprocs "nix-build" ["-A", "nixops", format fp defaultNix] $
                   (trace (T.unpack $ format ("INFO: using "%fp%" expression for its definition of 'nixops'") defaultNix) empty)
      path       = Path.fromText $ T.strip storePath <> "/bin/nixops"
  in trace (T.unpack $ format ("INFO: nixops is "%fp) path) path

nixops'' :: (Options -> Text -> [Text] -> IO b) -> Options -> NixopsConfig -> NixopsCmd -> [Arg] -> IO b
nixops'' executor o@Options{..} c@NixopsConfig{..} com args =
  executor o (format fp iohkNixopsPath)
    (fromCmd com : nixopsCmdOptions o c <> fmap fromArg args)

nixops'  :: Options -> NixopsConfig -> NixopsCmd -> [Arg] -> IO (ExitCode, Text)
nixops   :: Options -> NixopsConfig -> NixopsCmd -> [Arg] -> IO ()
nixops'  = nixops'' cmd'
nixops   = nixops'' cmd

nixopsMaybeLimitNodes :: Options -> [Arg]
nixopsMaybeLimitNodes (oOnlyOn -> maybeNode) = ((("--include":) . (:[]) . Arg . fromNodeName) <$> maybeNode & fromMaybe [])


-- * Deployment lifecycle
--
exists :: Options -> NixopsConfig -> IO Bool
exists o NixopsConfig{..} = do
  let ops = format fp iohkNixopsPath
  (code, _, _) <- cmd'' o (ops <> " info -d " <> (fromNixopsDepl cName))
  pure $ code == ExitSuccess

buildGlobalsImportNixExpr :: [(NixParam, NixValue)] -> NixValue
buildGlobalsImportNixExpr deplArgs =
  NixImport (NixFile "globals.nix")
  $ NixAttrSet $ Map.fromList $ (fromNixParam *** id) <$> deplArgs

computeFinalDeploymentArgs :: Options -> NixopsConfig -> IO [(NixParam, NixValue)]
computeFinalDeploymentArgs o@Options{..} NixopsConfig{..} = do
  IP deployerIP <- establishDeployerIP o oDeployerIP
  let deplArgs' = Map.toList cDeplArgs
                  <> [("deployerIP",   NixStr  deployerIP)
                     ,("topologyYaml", NixFile cTopology)
                     ,("environment",  NixStr  $ lowerShowT cEnvironment)]
  pure $ ("globals", buildGlobalsImportNixExpr deplArgs'): deplArgs'

modify :: Options -> NixopsConfig -> IO ()
modify o@Options{..} c@NixopsConfig{..} = do
  deplExists <- exists o c
  if deplExists
  then do
    printf ("Modifying pre-existing deployment "%s%"\n") $ fromNixopsDepl cName
    nixops o c "modify" $ Arg <$> cFiles
  else do
    printf ("Creating deployment "%s%"\n") $ fromNixopsDepl cName
    nixops o c "create" $ Arg <$> deploymentFiles cEnvironment cTarget cElements

  printf ("Setting deployment arguments:\n")
  deplArgs <- computeFinalDeploymentArgs o c
  forM_ deplArgs $ \(name, val)
    -> printf ("  "%s%": "%s%"\n") (fromNixParam name) (nixValueStr val)
  nixops o c "set-args" $ Arg <$> (concat $ uncurry nixArgCmdline <$> deplArgs)

  simpleTopo <- getSimpleTopo cElements cTopology
  liftIO . writeTextFile simpleTopoFile . T.pack . LBU.toString $ encodePretty (fromSimpleTopo simpleTopo)
  when (toBool oDebug) $ dumpTopologyNix c

setenv :: Options -> EnvVar -> Text -> IO ()
setenv o@Options{..} (EnvVar k) v = do
  export k v
  when (oVerbose == Verbose) $
    cmd o "/bin/sh" ["-c", format ("echo 'export "%s%"='$"%s) k k]

deploy :: Options -> NixopsConfig -> DryRun -> BuildOnly -> PassCheck -> Maybe Seconds -> IO ()
deploy o@Options{..} c@NixopsConfig{..} dryrun buonly check bumpSystemStartHeldBy = do
  when (elem Nodes cElements) $ do
     keyExists <- testfile "keys/key1.sk"
     unless keyExists $
       die "Deploying nodes, but 'keys/key1.sk' is absent."

  _ <- pure $ clusterConfigurationKey c
  let simulated        = dryrun == DryRun || buonly == BuildOnly
      hasNodesToDeploy = elem Nodes cElements
  unless simulated $ do
    deployerIP <- establishDeployerIP o oDeployerIP
    setenv o "SMART_GEN_IP" $ getIP deployerIP
  -- Pre-allocate nix heap to improve performance
  when hasNodesToDeploy $ case oInitialHeapSize of
    Just size -> setenv o "GC_INITIAL_HEAP_SIZE" (showT size)
    Nothing -> pure ()

  now <- timeCurrent
  let startParam             = NixParam "systemStart"
      secNixVal (Elapsed x)  = NixInt $ fromIntegral x
      holdSecs               = fromMaybe defaultHold bumpSystemStartHeldBy
      nowHeld                = now `timeAdd` mempty { durationSeconds = holdSecs }
      startE                 = case bumpSystemStartHeldBy of
        Just _  -> nowHeld
        Nothing -> Elapsed $ fromIntegral $ (\(NixInt x)-> x) $ deplArg c startParam (secNixVal nowHeld)
      c' = setDeplArg startParam (secNixVal startE) c
  when (isJust bumpSystemStartHeldBy) $ do
    let timePretty = (T.pack $ timePrint ISO8601_DateAndTime (timeFromElapsed startE :: DateTime))
    printf ("Setting --system-start to "%s%" ("%d%" minutes into future)\n")
           timePretty (div holdSecs 60)
    cFp <- writeConfig oConfigFile c'
    unless (cEnvironment == Development || cEnvironment == Benchmark) $ do
      cmd o "git" (["add", format fp cFp])
      cmd o "git" ["commit", "-m", format ("Bump systemStart to "%s) timePretty]

  modify o c'

  printf ("Deploying cluster "%s%"\n") $ fromNixopsDepl cName
  nixops o c' "deploy"
    $  [ "--max-concurrent-copy", "50", "-j", "4" ]
    ++ [ "--dry-run"       | dryrun == DryRun ]
    ++ [ "--build-only"    | buonly == BuildOnly ]
    ++ [ "--check"         | check  == PassCheck  ]
    ++ nixopsMaybeLimitNodes o

  when (hasNodesToDeploy && not simulated) $ do
    let cmonNode = head $ nodeNames o c'
    printf ("Triggering commit monitor on "%s%"\n") $ fromNodeName cmonNode
    triggerCommitMonitor o c' cmonNode

  echo "Done."

destroy :: Options -> NixopsConfig -> IO ()
destroy o c@NixopsConfig{..} = do
  printf ("Destroying cluster "%s%"\n") $ fromNixopsDepl cName
  nixops (o { oConfirm = Confirmed }) c "destroy"
    $ nixopsMaybeLimitNodes o
  echo "Done."

delete :: Options -> NixopsConfig -> IO ()
delete o c@NixopsConfig{..} = do
  printf ("Un-defining cluster "%s%"\n") $ fromNixopsDepl cName
  nixops (o { oConfirm = Confirmed }) c "delete"
    $ nixopsMaybeLimitNodes o
  echo "Done."

nodeDestroyElasticIP :: Options -> NixopsConfig -> NodeName -> IO ()
nodeDestroyElasticIP o c name =
  let nodeElasticIPResource :: NodeName -> Text
      nodeElasticIPResource = (<> "-ip") . fromNodeName
  in nixops (o { oConfirm = Confirmed }) c "destroy" ["--include", Arg $ nodeElasticIPResource name]


-- * Higher-level (deploy-based) scenarios
--
defaultDeploy :: Options -> NixopsConfig -> IO ()
defaultDeploy o c =
  deploy o c NoDryRun NoBuildOnly DontPassCheck (Just defaultHold)

fromscratch :: Options -> NixopsConfig -> IO ()
fromscratch o c = do
  destroy o c
  delete o c
  defaultDeploy o c

-- | Destroy elastic IPs corresponding to the nodes listed and reprovision cluster.
reallocateElasticIPs :: Options -> NixopsConfig -> [NodeName] -> IO ()
reallocateElasticIPs o c@NixopsConfig{..} nodes = do
  mapM_ (nodeDestroyElasticIP o c) nodes
  defaultDeploy o c

reallocateCoreIPs :: Options -> NixopsConfig -> IO ()
reallocateCoreIPs o c = reallocateElasticIPs o c (topoCores $ topology c)


-- * Building
--

buildAMI :: Options -> NixopsConfig -> IO ()
buildAMI o _ = do
  cmd o "nix-build" ["jobsets/cardano.nix", "-A", "cardano-node-image", "-o", "image"]
  cmd o "./scripts/create-amis.sh" []

dumpLogs :: Options -> NixopsConfig -> Bool -> IO Text
dumpLogs o c withProf = do
    TIO.putStrLn $ "WithProf: " <> T.pack (show withProf)
    when withProf $ do
        stop o c
        sleep 2
        echo "Dumping logs..."
    (_, dt) <- fmap T.strip <$> cmd' o "date" ["+%F_%H%M%S"]
    let workDir = "experiments/" <> dt
    TIO.putStrLn workDir
    cmd o "mkdir" ["-p", workDir]
    parallelIO o c $ dump workDir
    return dt
  where
    dump workDir node =
        forM_ logs $ \(rpath, fname) -> do
          scpFromNode o c node rpath (workDir <> "/" <> fname (fromNodeName node))
    logs = mconcat
             [ if withProf
                  then profLogs
                  else []
             , defLogs
             ]
prefetchURL :: Options -> Project -> Commit -> IO (NixHash, FilePath)
prefetchURL o proj rev = do
  let url = projectURL proj
  hashPath <- T.lines <$> incmd o "nix-prefetch-url" ["--unpack", "--print-path", (fromURL $ url) <> "/archive/" <> fromCommit rev <> ".tar.gz"]
  pure (NixHash (hashPath !! 0), Path.fromText $ hashPath !! 1)

runSetRev :: Options -> Project -> Commit -> Maybe Text -> IO ()
runSetRev o proj rev mCommitChanges = do
  printf ("Setting '"%s%"' commit to "%s%"\n") (lowerShowT proj) (fromCommit rev)
  let url = projectURL proj
  (hash, _) <- prefetchURL o proj rev
  printf ("Hash is"%s%"\n") (showT hash)
  let revspecFile = format fp $ projectSrcFile proj
      revSpec = GitSource{ gRev             = rev
                         , gUrl             = url
                         , gSha256          = hash
                         , gFetchSubmodules = True }
  writeFile (T.unpack $ revspecFile) $ LBU.toString $ encodePretty revSpec
  case mCommitChanges of
    Nothing  -> pure ()
    Just msg -> do
      cmd o "git" (["add", revspecFile])
      cmd o "git" ["commit", "-m", msg]

deploymentBuildTarget :: Deployment -> NixAttr
deploymentBuildTarget Nodes = "cardano-sl-static"
deploymentBuildTarget x     = error $ "'deploymentBuildTarget' has no idea what to build for " <> show x

build :: Options -> NixopsConfig -> Deployment -> IO ()
build o _c depl = do
  echo "Building derivation..."
  cmd o "nix-build" ["--max-jobs", "4", "--cores", "2", "-A", fromAttr $ deploymentBuildTarget depl]


-- | Use nix to grab the cardano-sl-config.
getCardanoSLConfig :: Options -> IO Path.FilePath
getCardanoSLConfig o = fromText <$> incmdStrip o "nix-build" args
  where args = [ "-A", "cardano-sl-config", "default.nix" ]


-- * State management
--
-- Check if nodes are online and reboots them if they timeout
checkstatus :: Options -> NixopsConfig -> IO ()
checkstatus o c = do
  parallelIO o c $ rebootIfDown o c

rebootIfDown :: Options -> NixopsConfig -> NodeName -> IO ()
rebootIfDown o c (Arg . fromNodeName -> node) = do
  (x, _) <- nixops' o c "ssh" $ (node : ["-o", "ConnectTimeout=5", "echo", "-n"])
  case x of
    ExitSuccess -> return ()
    ExitFailure _ -> do
      TIO.putStrLn $ "Rebooting " <> fromArg node
      nixops o c "reboot" ["--include", node]

ssh  :: Options -> NixopsConfig -> Exec -> [Arg] -> NodeName -> IO ()
ssh o c e a n = ssh' o c e a n (TIO.putStr . ((fromNodeName n <> "> ") <>))

ssh' :: Options -> NixopsConfig -> Exec -> [Arg] -> NodeName -> (Text -> IO ()) -> IO ()
ssh' o c exec args (fromNodeName -> node) postFn = do
  let cmdline = Arg node: "--": Arg (fromExec exec): args
  (exitcode, out) <- nixops' o c "ssh" cmdline
  postFn out
  case exitcode of
    ExitSuccess -> return ()
    ExitFailure code -> TIO.putStrLn $ "ssh cmd '" <> (T.intercalate " " $ fromArg <$> cmdline) <> "' to '" <> node <> "' failed with " <> showT code

parallelSSH :: Options -> NixopsConfig -> Exec -> [Arg] -> IO ()
parallelSSH o c@NixopsConfig{..} ex as = do
  parallelIO o c $
    ssh o c ex as

scpFromNode :: Options -> NixopsConfig -> NodeName -> Text -> Text -> IO ()
scpFromNode o c (fromNodeName -> node) from to = do
  (exitcode, _) <- nixops' o c "scp" $ Arg <$> ["--from", node, from, to]
  case exitcode of
    ExitSuccess -> return ()
    ExitFailure code -> TIO.putStrLn $ "scp from " <> node <> " failed with " <> showT code

-- To check logs for commit ID run `journalctl -n 1 --identifier=cardano-node-commit-monitor`
triggerCommitMonitor :: Options -> NixopsConfig -> NodeName -> IO ()
triggerCommitMonitor o c m =
  ssh' o c "bash" ["-c", "\"/proc/$(systemctl show -p MainPID --value cardano-node.service)/exe --version | sed 's/.* git revision \\([a-z0-9]\\)/\\1/' | xargs printf 'https://github.com/input-output-hk/cardano-sl/commit/%s' | systemd-cat -t cardano-node-commit-monitor -p info\""] m
  (const $ pure ())

deployedCommit :: Options -> NixopsConfig -> NodeName -> IO ()
deployedCommit o c m = do
  ssh' o c "pgrep" ["-fa", "cardano-node"] m $
    \r-> do
      case cut space r of
        (_:path:_) -> do
          drv <- incmdStrip o "nix-store" ["--query", "--deriver", T.strip path]
          pathExists <- testpath $ fromText drv
          unless pathExists $
            errorT $ "The derivation used to build the package is not present on the system: " <> T.strip drv
          sh $ do
            str <- inproc "nix-store" ["--query", "--references", T.strip drv] empty &
                   inproc "egrep"       ["/nix/store/[a-z0-9]*-cardano-sl-[0-9a-f]{7}\\.drv"] &
                   inproc "sed" ["-E", "s|/nix/store/[a-z0-9]*-cardano-sl-([0-9a-f]{7})\\.drv|\\1|"]
            when (str == "") $
              errorT $ "Cannot determine commit id for derivation: " <> T.strip drv
            echo $ "The 'cardano-sl' process running on '" <> unsafeTextToLine (fromNodeName m) <> "' has commit id " <> str
        [""] -> errorT $ "Looks like 'cardano-node' is down on node '" <> fromNodeName m <> "'"
        _    -> errorT $ "Unexpected output from 'pgrep -fa cardano-node': '" <> r <> "' / " <> showT (cut space r)


startForeground :: Options -> NixopsConfig -> NodeName -> IO ()
startForeground o c node =
  ssh' o c "bash" [ "-c", "'systemctl show cardano-node --property=ExecStart | sed -e \"s/.*path=\\([^ ]*\\) .*/\\1/\" | xargs grep \"^exec \" | cut -d\" \" -f2-'"]
  node $ \unitStartCmd ->
    printf ("Starting Cardano in foreground;  Command line:\n  "%s%"\n") unitStartCmd >>
    ssh o c "bash" ["-c", Arg $ "'sudo -u cardano-node " <> unitStartCmd <> "'"] node

stop :: Options -> NixopsConfig -> IO ()
stop o c = echo (unsafeTextToLine $ "Stopping " <> (fst $ scopeNameDesc o c))
  >> parallelSSH o c "systemctl" ["stop", "cardano-node"]

defLogs, profLogs :: [(Text, Text -> Text)]
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

start :: Options -> NixopsConfig -> IO ()
start o c =
  parallelSSH o c "bash" ["-c", Arg $ "'" <> rmCmd <> "; " <> startCmd <> "'"]
  where
    rmCmd = foldl (\str (f, _) -> str <> " " <> f) "rm -f" logs
    startCmd = "systemctl start cardano-node"
    logs = mconcat [ defLogs, profLogs ]

date :: Options -> NixopsConfig -> IO ()
date o c = parallelIO o c $
  \n -> ssh' o c "date" [] n
  (\out -> TIO.putStrLn $ fromNodeName n <> ": " <> out)

configurationKeys :: Environment -> Arch -> T.Text
configurationKeys Production Win64   = "mainnet_wallet_win64"
configurationKeys Production Mac64   = "mainnet_wallet_macos64"
configurationKeys Production Linux64 = "mainnet_wallet_linux64"
configurationKeys Staging    Win64   = "mainnet_dryrun_wallet_win64"
configurationKeys Staging    Mac64   = "mainnet_dryrun_wallet_macos64"
configurationKeys Staging    Linux64 = "mainnet_dryrun_wallet_linux64"
configurationKeys Testnet    Win64   = "testnet_wallet_win64"
configurationKeys Testnet    Mac64   = "testnet_wallet_macos64"
configurationKeys Testnet    Linux64 = "testnet_wallet_linux64"
configurationKeys env _ = error $ "Application versions not used in '" <> show env <> "' environment"

findInstallers :: NixopsConfig -> T.Text -> Maybe FilePath
               -> Maybe Int -> Maybe Int -> IO ()
findInstallers c daedalusRev destDir bkNum avNum = do
  let instP = selectBuildNumberPredicate bkNum avNum
  installers <- getInstallersResults (configurationKeys $ cEnvironment c) instP daedalusRev destDir
  printInstallersResults installers
  case destDir of
    Just dir -> void $ proc "ls" [ "-ltrha", tt dir ] mempty
    Nothing -> pure ()

wipeJournals :: Options -> NixopsConfig -> IO ()
wipeJournals o c@NixopsConfig{..} = do
  echo $ unsafeTextToLine $ "Wiping journals on " <> (fst $ scopeNameDesc o c)
  parallelSSH o c "bash"
    ["-c", "'systemctl --quiet stop systemd-journald && rm -f /var/log/journal/*/* && systemctl start systemd-journald && sleep 1 && systemctl restart nix-daemon'"]
  echo "Done."

getJournals :: Options -> NixopsConfig -> JournaldTimeSpec -> Maybe JournaldTimeSpec -> IO ()
getJournals o c@NixopsConfig{..} timesince mtimeuntil = do
  let nodes = nodeNames o c
      (scName, scDesc) = scopeNameDesc o c

  echo $ unsafeTextToLine $ "Dumping journald logs on " <> scName
  parallelSSH o c "bash"
    ["-c", Arg $ "'rm -f log && journalctl -u cardano-node --since \"" <> fromJournaldTimeSpec timesince <> "\""
      <> fromMaybe "" ((\timeuntil-> " --until \"" <> fromJournaldTimeSpec timeuntil <> "\"") <$> mtimeuntil)
      <> " > log'"]

  echo "Obtaining dumped journals.."
  let outfiles  = format ("log-cardano-node-"%s%".journal") . fromNodeName <$> nodes
  parallelIO' o c (flip zip outfiles) $
    \(node, outfile) -> scpFromNode o c node "log" outfile
  timeStr <- T.replace ":" "_" . T.pack . timePrint ISO8601_DateAndTime <$> dateCurrent

  let archive   = format ("journals-"%s%"-"%s%"-"%s%".tgz") (lowerShowT cEnvironment) scDesc timeStr
  printf ("Packing journals into "%s%"\n") archive
  cmd o "tar" (["czf", archive] <> outfiles)
  cmd o "rm" $ "-f" : outfiles
  echo "Done."

wipeNodeDBs :: Options -> NixopsConfig -> Confirmation -> IO ()
wipeNodeDBs o c@NixopsConfig{..} confirmation = do
  echo $ unsafeTextToLine $ "About to wipe node databases on " <> (fst $ scopeNameDesc o c)
  confirmOrTerminate confirmation
  echo "Wiping node databases.."
  parallelSSH o c "rm" ["-rf", "/var/lib/cardano-node"]
  echo "Done."



-- * Functions for extracting information out of nixops info command
--
-- | Get all nodes in EC2 cluster
data DeploymentStatus = UpToDate | Obsolete | Outdated
  deriving (Show, Eq)

instance FromField DeploymentStatus where
  parseField "up-to-date" = pure UpToDate
  parseField "obsolete" = pure Obsolete
  parseField "outdated" = pure Outdated
  parseField _ = mzero

data DeploymentInfo = DeploymentInfo
    { diName :: !NodeName
    , diStatus :: !DeploymentStatus
    , diType :: !Text
    , diResourceID :: !Text
    , diPublicIP :: !IP
    , diPrivateIP :: !IP
    } deriving (Show, Generic)

instance FromRecord DeploymentInfo
deriving instance FromField NodeName

nixopsDecodeOptions = defaultDecodeOptions {
    decDelimiter = fromIntegral (ord '\t')
  }

info :: Options -> NixopsConfig -> IO (Either String (V.Vector DeploymentInfo))
info o c = do
  (exitcode, nodes) <- nixops' o c "info" ["--no-eval", "--plain"]
  case exitcode of
    ExitFailure code -> return $ Left ("Parsing info failed with exit code " <> show code)
    ExitSuccess -> return $ decodeWith nixopsDecodeOptions NoHeader (encodeUtf8 $ fromStrict nodes)

toNodesInfo :: V.Vector DeploymentInfo -> [DeploymentInfo]
toNodesInfo vector =
  V.toList $ V.filter filterEC2 vector
    where
      filterEC2 di = T.take 4 (diType di) == "ec2 " && diStatus di /= Obsolete

getNodePublicIP :: Text -> V.Vector DeploymentInfo -> Maybe Text
getNodePublicIP name vector =
    headMay $ V.toList $ fmap (getIP . diPublicIP) $ V.filter (\di -> fromNodeName (diName di) == name) vector
