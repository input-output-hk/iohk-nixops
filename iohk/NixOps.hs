{-# OPTIONS_GHC -Wall -Wno-orphans -Wno-missing-signatures -Wno-unticked-promoted-constructors -Wno-type-defaults #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ViewPatterns #-}

module NixOps where

import           Control.Exception                (throwIO)
import           Control.Lens                     ((<&>))
import           Control.Monad                    (forM_)
import qualified Data.Aeson                    as AE
import           Data.Aeson                       ((.:), (.=))
import qualified Data.Aeson.Types              as AE
import           Data.Aeson.Encode.Pretty         (encodePretty)
import qualified Data.ByteString.Lazy          as BL
import           Data.ByteString.Lazy.Char8       (ByteString)
import qualified Data.ByteString.UTF8          as BU
import qualified Data.ByteString.Lazy.UTF8     as LBU
import           Data.Char                        (ord, toLower)
import           Data.Csv                         (decodeWith, FromRecord(..), FromField(..), HasHeader(..), defaultDecodeOptions, decDelimiter)
import           Data.Either
import           Data.Hourglass                   (timePrint, ISO8601_DateAndTime(..))
import           Data.List                        (sort)
import           Data.Maybe
import qualified Data.Map                      as Map
import           Data.Monoid                      ((<>))
import qualified Data.Set                      as Set
import qualified Data.Text                     as T
import qualified Data.Text.IO                  as TIO
import           Data.Text.Lazy                   (fromStrict)
import           Data.Text.Lazy.Encoding          (encodeUtf8)
import qualified Data.Vector                   as V
import qualified Data.Yaml                     as YAML
import           Data.Yaml                        (FromJSON(..), ToJSON(..))
import qualified Filesystem.Path.CurrentOS     as Path
import           GHC.Generics              hiding (from, to)
import           Prelude                   hiding (FilePath)
import           Safe                             (headMay)
import qualified System.IO                     as Sys
import           Time.System
import           Time.Types
import           Turtle                    hiding (env, err, fold, inproc, prefix, procs, e, f, o, x)
import qualified Turtle                        as Turtle


import           Topology


-- * Constants
--
awsPublicIPURL :: URL
awsPublicIPURL = "http://169.254.169.254/latest/meta-data/public-ipv4"

defaultEnvironment   = Development
defaultTarget        = AWS
defaultNode          = NodeName "c-a-1"
defaultNodePort      = PortNo 3000

hardcodedHold, defaultHold :: Seconds
hardcodedHold        = 3600 -- The hold-off fime hard-coded in cardano-sl, in seconds
defaultHold          = 3600


-- * Projects
--
data Project
  = CardanoSL
  | CardanoExplorer
  | IOHK
  | Nixpkgs
  | Stack2nix
  | Nixops
  deriving (Bounded, Enum, Eq, Read, Show)

every :: (Bounded a, Enum a) => [a]
every = enumFromTo minBound maxBound

projectURL     :: Project -> URL
projectURL     CardanoSL       = "https://github.com/input-output-hk/cardano-sl.git"
projectURL     CardanoExplorer = "https://github.com/input-output-hk/cardano-sl-explorer.git"
projectURL     IOHK            = "https://github.com/input-output-hk/iohk-nixops.git"
projectURL     Nixpkgs         = "https://github.com/nixos/nixpkgs.git"
projectURL     Stack2nix       = "https://github.com/input-output-hk/stack2nix.git"
projectURL     Nixops          = "https://github.com/input-output-hk/nixops.git"

projectSrcFile :: Project -> FilePath
projectSrcFile CardanoSL       = "cardano-sl-src.json"
projectSrcFile CardanoExplorer = "cardano-sl-explorer-src.json"
projectSrcFile Nixpkgs         = "nixpkgs-src.json"
projectSrcFile Stack2nix       = "stack2nix-src.json"
projectSrcFile IOHK            = error "Feeling self-referential?"
projectSrcFile Nixops          = error "No corresponding -src.json spec for 'nixops' yet."


-- * Primitive types
--
newtype Branch    = Branch    { fromBranch  :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype Commit    = Commit    { fromCommit  :: Text } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype NixParam  = NixParam  { fromNixParam :: Text } deriving (FromJSON, Generic, Show, IsString, Eq, Ord, AE.ToJSONKey, AE.FromJSONKey)
newtype NixHash   = NixHash   { fromNixHash :: Text } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype NixAttr   = NixAttr   { fromAttr    :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype NixopsCmd = NixopsCmd { fromCmd     :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype Region    = Region    { fromRegion  :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype URL       = URL       { fromURL     :: Text } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype FQDN      = FQDN      { fromFQDN    :: Text } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype IP        = IP        { getIP       :: Text } deriving (Show, Generic, FromField)
newtype PortNo    = PortNo    { fromPortNo  :: Int  } deriving (FromJSON, Generic, Show, ToJSON)

deriving instance Read NodeName
deriving instance AE.ToJSONKey NodeName
fromNodeName :: NodeName -> Text
fromNodeName (NodeName x) = x


-- * Some orphan instances..
--
instance FromJSON FilePath where parseJSON = AE.withText "filepath" $ \v -> pure $ fromText v
instance ToJSON   FilePath where toJSON    = AE.String . format fp
deriving instance Generic Seconds
instance FromJSON Seconds


-- * A bit of Nix types
--
data SourceKind = Git | Github

data NixSource (a :: SourceKind) where
  -- | The output of 'nix-prefetch-git'
  GitSource ::
    { gUrl             :: URL
    , gRev             :: Commit
    , gSha256          :: NixHash
    , gFetchSubmodules :: Bool
    } -> NixSource Git
  GithubSource ::
    { ghOwner           :: Text
    , ghRepo            :: Text
    , ghRev             :: Commit
    , ghSha256          :: NixHash
    } -> NixSource Github
deriving instance Show (NixSource a)
instance FromJSON (NixSource Git) where
  parseJSON = AE.withObject "GitSource" $ \v -> GitSource
      <$> v .: "url"
      <*> v .: "rev"
      <*> v .: "sha256"
      <*> v .: "fetchSubmodules"
instance FromJSON (NixSource Github) where
  parseJSON = AE.withObject "GithubSource" $ \v -> GithubSource
      <$> v .: "owner"
      <*> v .: "repo"
      <*> v .: "rev"
      <*> v .: "sha256"

githubSource :: ByteString -> Maybe (NixSource Github)
githubSource = AE.decode
gitSource    :: ByteString -> Maybe (NixSource Git)
gitSource    = AE.decode

readSource :: (ByteString -> Maybe (NixSource a)) -> Project -> IO (NixSource a)
readSource parser (projectSrcFile -> path) =
  (fromMaybe (errorT $ format ("File doesn't parse as NixSource: "%fp) path) . parser)
  <$> BL.readFile (T.unpack $ format fp path)

nixpkgsNixosURL :: Commit -> URL
nixpkgsNixosURL (Commit rev) = URL $
  "https://github.com/NixOS/nixpkgs/archive/" <> rev <> ".tar.gz"

-- | The set of first-class types present in Nix
data NixValue
  = NixBool Bool
  | NixInt  Integer
  | NixStr  Text
  | NixFile FilePath
  deriving (Generic, Show)
instance FromJSON NixValue
instance ToJSON NixValue

nixValueStr :: NixValue -> Text
nixValueStr (NixBool bool) = T.toLower $ showT bool
nixValueStr (NixInt  int)  = showT int
nixValueStr (NixStr  str)  = str
nixValueStr (NixFile f)    = let txt = format fp f
                             in if T.isPrefixOf "/" txt
                                then txt else ("./" <> txt)

nixArgCmdline :: NixParam -> NixValue -> [Text]
nixArgCmdline (NixParam name) x@(NixBool _) = ["--arg",    name, nixValueStr x]
nixArgCmdline (NixParam name) x@(NixInt  _) = ["--arg",    name, nixValueStr x]
nixArgCmdline (NixParam name) x@(NixStr  _) = ["--argstr", name, nixValueStr x]
nixArgCmdline (NixParam name) x@(NixFile _) = ["--arg",    name, nixValueStr x]


-- * Domain
--
data Deployment
  = Explorer
  | Nodes
  | Infra
  | ReportServer
  | Timewarp
  deriving (Bounded, Eq, Enum, Generic, Read, Show)
instance FromJSON Deployment

data Environment
  = Any               -- ^ Wildcard or unspecified, depending on context.
  | Production
  | Staging
  | Development
  deriving (Bounded, Eq, Enum, Generic, Read, Show)
instance FromJSON Environment

data Target
  = All               -- ^ Wildcard or unspecified, depending on context.
  | AWS
  deriving (Bounded, Eq, Enum, Generic, Read, Show)
instance FromJSON Target

envConfigFilename :: IsString s => Environment -> s
envConfigFilename Any           = "config.yaml"
envConfigFilename Development   = "config.yaml"
envConfigFilename Staging       = "staging.yaml"
envConfigFilename Production    = "production.yaml"

selectDeployer :: Environment -> [Deployment] -> NodeName
selectDeployer Staging delts | elem Nodes delts = "iohk"
                             | otherwise        = "cardano-deployer"
selectDeployer _ _                              = "cardano-deployer"

selectTopologyConfig :: Environment -> [Deployment] -> FilePath
selectTopologyConfig Development _ = "topology-development.yaml"
selectTopologyConfig _           _ = "topology.yaml"

type DeplArgs = Map.Map NixParam NixValue

deployerIP :: Options -> IO IP
deployerIP o = IP <$> incmd o "curl" ["--silent", fromURL awsPublicIPURL]

selectDeploymentArgs :: Options -> FilePath -> Environment -> [Deployment] -> IO DeplArgs
selectDeploymentArgs o _ env delts = do
    let staticArgs = [ ("accessKeyId"
                       , NixStr . fromNodeName $ selectDeployer env delts) ]
    (IP deployerIp) <- deployerIP o
    pure $ Map.fromList $
      staticArgs
      <> [ ("deployerIP",   NixStr deployerIp) ]


-- * Topology
--
readTopology :: FilePath -> IO Topology
readTopology file = do
  eTopo <- liftIO $ YAML.decodeFileEither $ Path.encodeString file
  case eTopo of
    Right (topology :: Topology) -> pure topology
    Left err -> errorT $ format ("Failed to parse topology file: "%fp%": "%w) file err

data SimpleTopo
  =  SimpleTopo (Map.Map NodeName SimpleNode)
  deriving (Generic, Show)
instance ToJSON SimpleTopo
data SimpleNode
  =  SimpleNode
     { snType     :: NodeType
     , snRegion   :: NodeRegion
     , snFQDN     :: FQDN
     , snPort     :: PortNo
     , snInPeers  :: [NodeName]                  -- ^ Incoming connection edges
     , snKademlia :: RunKademlia
     } deriving (Generic, Show)
instance ToJSON SimpleNode where-- toJSON = jsonLowerStrip 2
  toJSON SimpleNode{..} = AE.object
   [ "type"        .= (lowerShowT snType & T.stripPrefix "node"
                        & fromMaybe (error "A NodeType constructor gone mad: doesn't start with 'Node'."))
   , "address"     .= fromFQDN snFQDN
   , "port"        .= fromPortNo snPort
   , "peers"       .= snInPeers
   , "region"      .= snRegion
   , "kademlia"    .= snKademlia ]
instance ToJSON NodeRegion
instance ToJSON NodeName
deriving instance Generic NodeName
deriving instance Generic NodeRegion
deriving instance Generic NodeType
instance ToJSON NodeType

summariseTopology :: Topology -> SimpleTopo
summariseTopology (TopologyStatic (AllStaticallyKnownPeers nodeMap)) =
  SimpleTopo $ Map.mapWithKey simplifier nodeMap
  where simplifier node (NodeMetadata snType snRegion (NodeRoutes outRoutes) nmAddr snKademlia) =
          SimpleNode{..}
          where (mPort,  fqdn)   = case nmAddr of
                                     (NodeAddrExact fqdn'  mPort') -> (mPort', fqdn') -- (Ok, bizarrely, this contains FQDNs, even if, well.. : -)
                                     (NodeAddrDNS   mFqdn  mPort') -> (mPort', flip fromMaybe mFqdn
                                                                      $ error "Cannot deploy a topology with nodes lacking a FQDN address.")
                (snPort, snFQDN) = (,) (fromMaybe defaultNodePort $ PortNo . fromIntegral <$> mPort)
                                   $ (FQDN . T.pack . BU.toString) $ fqdn
                snInPeers = Set.toList . Set.fromList
                            $ [ other
                            | (other, (NodeMetadata _ _ (NodeRoutes routes) _ _)) <- Map.toList nodeMap
                            , elem node (concat routes) ]
                            <> concat outRoutes
summariseTopology x = errorT $ format ("Unsupported topology type: "%w) x

dumpTopologyNix :: FilePath -> IO ()
dumpTopologyNix topo = sh $ do
  let nodeSpecExpr prefix =
        format ("with (import <nixpkgs> {}); "%s%" (import deployments/cardano-nodes-config.nix { accessKeyId = \"\"; deployerIP = \"\"; topologyFile = "%fp%"; })") prefix topo
      getNodeArgsAttr prefix attr = inproc "nix-instantiate" ["--strict", "--show-trace", "--eval" ,"-E", nodeSpecExpr prefix <> "." <> attr] empty
      liftNixList = inproc "sed" ["s/\" \"/\", \"/g"]
  (cores  :: [NodeName]) <- getNodeArgsAttr "map (x: x.name)" "cores"  & liftNixList <&> ((NodeName <$>) . readT . lineToText)
  (relays :: [NodeName]) <- getNodeArgsAttr "map (x: x.name)" "relays" & liftNixList <&> ((NodeName <$>) . readT . lineToText)
  echo "Cores:"
  forM_ cores  $ \(NodeName x) -> do
    printf ("  "%s%"\n    ") x
    Turtle.proc "nix-instantiate" ["--strict", "--show-trace", "--eval" ,"-E", nodeSpecExpr "" <> ".nodeArgs." <> x] empty
  echo "Relays:"
  forM_ relays $ \(NodeName x) -> do
    printf ("  "%s%"\n    ") x
    Turtle.proc "nix-instantiate" ["--strict", "--show-trace", "--eval" ,"-E", nodeSpecExpr "" <> ".nodeArgs." <> x] empty


-- * deployment structure
--
type FileSpec = (Environment, Target, Text)

deployments :: [(Deployment, [FileSpec])]
deployments =
  [ (Explorer
    , [ (Any,         All, "deployments/cardano-explorer.nix")
      , (Development, All, "deployments/cardano-explorer-env-development.nix")
      , (Production,  All, "deployments/cardano-explorer-env-production.nix")
      , (Staging,     All, "deployments/cardano-explorer-env-staging.nix")
      , (Any,         AWS, "deployments/cardano-explorer-target-aws.nix") ])
  , (Nodes
    , [ (Any,         All, "deployments/cardano-nodes.nix")
      , (Development, All, "deployments/cardano-nodes-env-development.nix")
      , (Production,  All, "deployments/cardano-nodes-env-production.nix")
      , (Staging,     All, "deployments/cardano-nodes-env-staging.nix")
      , (Any,         AWS, "deployments/cardano-nodes-target-aws.nix") ])
  , (Infra
    , [ (Any,         All, "deployments/infrastructure.nix")
      , (Production,  All, "deployments/infrastructure-env-production.nix")
      , (Any,         AWS, "deployments/infrastructure-target-aws.nix") ])
  , (ReportServer
    , [ (Any,         All, "deployments/report-server.nix")
      , (Production,  All, "deployments/report-server-env-production.nix")
      , (Staging,     All, "deployments/report-server-env-staging.nix")
      , (Any,         AWS, "deployments/report-server-target-aws.nix") ])
  , (Timewarp
    , [ (Any,         All, "deployments/timewarp.nix")
      , (Any,         AWS, "deployments/timewarp-target-aws.nix") ])
  ]

deploymentSpecs :: Deployment -> [FileSpec]
deploymentSpecs = fromJust . flip lookup deployments

filespecEnvSpecific :: Environment -> FileSpec -> Bool
filespecEnvSpecific x (x', _, _) = x == x'
filespecTgtSpecific :: Target      -> FileSpec -> Bool
filespecTgtSpecific x (_, x', _) = x == x'

filespecNeededEnv :: Environment -> FileSpec -> Bool
filespecNeededTgt :: Target      -> FileSpec -> Bool
filespecNeededEnv x fs = filespecEnvSpecific Any fs || filespecEnvSpecific x fs
filespecNeededTgt x fs = filespecTgtSpecific All fs || filespecTgtSpecific x fs

filespecFile :: FileSpec -> Text
filespecFile (_, _, x) = x

elementDeploymentFiles :: Environment -> Target -> Deployment -> [Text]
elementDeploymentFiles env tgt depl = filespecFile <$> (filter (\x -> filespecNeededEnv env x && filespecNeededTgt tgt x) $ deploymentSpecs depl)


data Options = Options
  { oConfigFile       :: Maybe FilePath
  , oConfirm          :: Bool
  , oDebug            :: Bool
  , oSerial           :: Bool
  , oVerbose          :: Bool
  } deriving Show

parserOptions :: Parser Options
parserOptions = Options
                <$> optional (optPath "config"  'c' "Configuration file")
                <*> switch  "confirm" 'y' "Pass --confirm to nixops"
                <*> switch  "debug"   'd' "Pass --debug to nixops"
                <*> switch  "serial"  's' "Disable parallelisation"
                <*> switch  "verbose" 'v' "Print all commands that are being run"

nixpkgsCommitPath :: Commit -> Text
nixpkgsCommitPath = ("nixpkgs=" <>) . fromURL . nixpkgsNixosURL

nixopsCmdOptions :: Options -> NixopsConfig -> [Text]
nixopsCmdOptions Options{..} NixopsConfig{..} =
  ["--debug"   | oDebug]   <>
  ["--confirm" | oConfirm] <>
  ["--show-trace"
  ,"--deployment", cName
  ,"-I", nixpkgsCommitPath cNixpkgsCommit
  ]


data NixopsConfig = NixopsConfig
  { cName             :: Text
  , cNixops           :: Maybe FilePath
  , cNixpkgsCommit    :: Commit
  , cTopology         :: FilePath
  , cEnvironment      :: Environment
  , cTarget           :: Target
  , cElements         :: [Deployment]
  , cFiles            :: [Text]
  , cDeplArgs         :: DeplArgs
  } deriving (Generic, Show)
instance FromJSON NixopsConfig where
    parseJSON = AE.withObject "NixopsConfig" $ \v -> NixopsConfig
        <$> v .: "name"
        <*> v .: "nixops"
        <*> v .: "nixpkgs"
        <*> v .: "topology"
        <*> v .: "environment"
        <*> v .: "target"
        <*> v .: "elements"
        <*> v .: "files"
        <*> v .: "args"
instance ToJSON Environment
instance ToJSON Target
instance ToJSON Deployment
instance ToJSON NixopsConfig where
  toJSON NixopsConfig{..} = AE.object
   [ "name"        .= cName
   , "nixops"      .= cNixops
   , "nixpkgs"     .= fromCommit cNixpkgsCommit
   , "topology"    .= cTopology
   , "environment" .= showT cEnvironment
   , "target"      .= showT cTarget
   , "elements"    .= cElements
   , "files"       .= cFiles
   , "args"        .= cDeplArgs ]

deploymentFiles :: Environment -> Target -> [Deployment] -> [Text]
deploymentFiles cEnvironment cTarget cElements =
  "deployments/firewalls.nix":
  "deployments/keypairs.nix":
  concat (elementDeploymentFiles cEnvironment cTarget <$> cElements)

-- | Interpret inputs into a NixopsConfig
mkConfig :: Options -> Branch -> Maybe FilePath -> Maybe FilePath -> Commit -> Environment -> Target -> [Deployment] -> IO NixopsConfig
mkConfig o (Branch cName) cNixops mTopology cNixpkgsCommit cEnvironment cTarget cElements = do
  let cFiles    = deploymentFiles                cEnvironment cTarget cElements
      cTopology = flip fromMaybe mTopology $
                  selectTopologyConfig           cEnvironment         cElements
  cDeplArgs <- selectDeploymentArgs  o cTopology cEnvironment         cElements
  pure NixopsConfig{..}

-- | Write the config file
writeConfig :: MonadIO m => Maybe FilePath -> NixopsConfig -> m FilePath
writeConfig mFp c@NixopsConfig{..} = do
  let configFilename = flip fromMaybe mFp $ envConfigFilename cEnvironment
  liftIO $ writeTextFile configFilename $ T.pack $ BU.toString $ YAML.encode c
  pure configFilename

-- | Read back config, doing validation
readConfig :: MonadIO m => FilePath -> m NixopsConfig
readConfig cf = do
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
  unless (storedFileSet == deducedFileSet) $
    die $ format ("Config file '"%fp%"' is incoherent with respect to elements "%w%":\n  - stored files:  "%w%"\n  - implied files: "%w%"\n")
          cf cElements (sort cFiles) (sort deducedFiles)
  pure c


parallelIO :: Options -> [IO a] -> IO ()
parallelIO Options{..} =
  if oSerial
  then sequence_
  else sh . parallel

logCmd  bin args = do
  printf ("-- "%s%"\n") $ T.intercalate " " $ bin:args
  Sys.hFlush Sys.stdout

inproc :: Text -> [Text] -> Shell Line -> Shell Line
inproc bin args inp = do
  liftIO $ logCmd bin args
  Turtle.inproc bin args inp

inprocs :: MonadIO m => Text -> [Text] -> Shell Line -> m Text
inprocs bin args inp = do
  (exitCode, out) <- liftIO $ procStrict bin args inp
  unless (exitCode == ExitSuccess) $
    liftIO (throwIO (ProcFailed bin args exitCode))
  pure out

cmd   :: Options -> Text -> [Text] -> IO ()
cmd'  :: Options -> Text -> [Text] -> IO (ExitCode, Text)
incmd :: Options -> Text -> [Text] -> IO Text

cmd   Options{..} bin args = do
  when oVerbose $ logCmd bin args
  Turtle.procs      bin args empty
cmd'  Options{..} bin args = do
  when oVerbose $ logCmd bin args
  Turtle.procStrict bin args empty
incmd Options{..} bin args = do
  when oVerbose $ logCmd bin args
  inprocs bin args empty


-- * Invoking nixops
--
nixopsPath :: NixopsConfig -> FilePath
nixopsPath = fromMaybe "nixops" . cNixops

nixops  :: Options -> NixopsConfig -> NixopsCmd -> [Text] -> IO ()
nixops' :: Options -> NixopsConfig -> NixopsCmd -> [Text] -> IO (ExitCode, Text)

nixops  o c (NixopsCmd com) args = cmd  o (format fp $ nixopsPath c) (com : nixopsCmdOptions o c <> args)
nixops' o c (NixopsCmd com) args = cmd' o (format fp $ nixopsPath c) (com : nixopsCmdOptions o c <> args)


-- * Deployment lifecycle
--
exists :: Options -> NixopsConfig -> IO Bool
exists o c@NixopsConfig{..} = do
  (code, _) <- nixops' o c "info" []
  pure $ code == ExitSuccess

create :: Options -> NixopsConfig -> IO ()
create o c@NixopsConfig{..} = do
  deplExists <- exists o c
  when deplExists $
    die $ format ("Deployment already exists?: '"%s%"'") cName
  printf ("Creating deployment "%s%"\n") cName
  export "NIX_PATH_LOCKED" "1"
  export "NIX_PATH" (nixpkgsCommitPath cNixpkgsCommit)
  nixops o c "create" $ deploymentFiles cEnvironment cTarget cElements

modify :: Options -> NixopsConfig -> IO ()
modify o@Options{..} c@NixopsConfig{..} = do
  printf ("Syncing Nix->state for deployment "%s%"\n") cName
  nixops o c "modify" $ deploymentFiles cEnvironment cTarget cElements

  let deplArgs = Map.toList cDeplArgs
                 <> [("topologyYaml", NixFile $ cTopology)] -- A special case, to avoid duplication.
  printf ("Setting deployment arguments:\n")
  forM_ deplArgs $ \(name, val)
    -> printf ("  "%s%": "%s%"\n") (fromNixParam name) (nixValueStr val)
  nixops o c "set-args" $ concat $ uncurry nixArgCmdline <$> deplArgs

  printf ("Generating 'topology.nix' from '"%fp%"'..\n") cTopology
  preExisting <- testpath cTopology
  unless preExisting $
    die $ format ("Topology config '"%fp%"' doesn't exist.") cTopology
  simpleTopo <- summariseTopology <$> readTopology cTopology
  liftIO . writeTextFile "topology.nix" . T.pack . LBU.toString $ encodePretty simpleTopo
  when oDebug $ dumpTopologyNix "./topology.nix"

deploy :: Options -> NixopsConfig -> Bool -> Bool -> Bool -> Bool -> Seconds -> IO ()
deploy o c@NixopsConfig{..} evonly buonly check bumpSystemStart hold = do
  when (elem Nodes cElements) $ do
     keyExists <- testfile "keys/key1.sk"
     unless keyExists $
       die "Deploying nodes, but 'keys/key1.sk' is absent."

  printf ("Deploying cluster "%s%"\n") cName
  export "NIX_PATH_LOCKED" "1"
  export "NIX_PATH" (nixpkgsCommitPath cNixpkgsCommit)
  when (not evonly) $ do
    when (elem Nodes cElements) $ do
      export "GC_INITIAL_HEAP_SIZE" (showT $ 8 * 1024*1024*1024) -- for 100 nodes it eats 12GB of ram *and* needs a bigger heap
    export "SMART_GEN_IP"     =<< getIP <$> deployerIP o
    when (elem Explorer cElements) $ do
      cmd o "scripts/generate-explorer-frontend.sh" []

  modify o c

  when bumpSystemStart $ do
    (Elapsed now) <- timeCurrent
    let start :: Seconds = now + hold - hardcodedHold
    printf ("Bumping system-start to "%d%" ("%d%" minutes into future).  Don't forget to commit!\n") start (div hold 60)
    writeTextFile "config-system-start.nix" $ T.pack $ show (fromIntegral start :: Int)

  nixops o c "deploy" $
    [ "--max-concurrent-copy", "50", "-j", "4" ]
    ++ [ "--evaluate-only" | evonly ]
    ++ [ "--build-only"    | buonly ]
    ++ [ "--check"         | check ]
  echo "Done."

destroy :: Options -> NixopsConfig -> IO ()
destroy o c@NixopsConfig{..} = do
  printf ("Destroying cluster "%s%"\n") cName
  nixops (o { oConfirm = True }) c "destroy" []
  echo "Done."

delete :: Options -> NixopsConfig -> IO ()
delete o c@NixopsConfig{..} = do
  printf ("Un-defining cluster "%s%"\n") cName
  nixops (o { oConfirm = True }) c "delete" []
  echo "Done."

fromscratch :: Options -> NixopsConfig -> IO ()
fromscratch o c = do
  destroy o c
  delete o c
  create o c
  deploy o c False False False True defaultHold


-- * Building
--
generateGenesis :: Options -> NixopsConfig -> IO ()
generateGenesis o _c = do
  let cardanoSLDir         = "cardano-sl"
  GitSource{..} <- readSource gitSource CardanoSL
  printf ("Generating genesis using cardano-sl commit "%s%"\n") $ fromCommit gRev
  preExisting <- testpath cardanoSLDir
  unless preExisting $
    cmd o "git" ["clone", fromURL $ projectURL CardanoSL, "cardano-sl"]
  cd "cardano-sl"
  cmd o "git" ["fetch"]
  cmd o "git" ["reset", "--hard", fromCommit gRev]
  cd ".."
  export "M" "14"
  cmd o "cardano-sl/scripts/generate/genesis.sh" ["genesis"]
-- M=14 NIX_PATH=nixpkgs=https://github.com/NixOS/nixpkgs/archive/7648f528de9917933bc104359c9a507c6622925c.tar.gz ./util-scripts/generate-genesis.sh
-- cp genesis-qanet-2017-06-13/core/genesis-core.bin core/genesis-core.bin
-- cp genesis-qanet-2017-06-13/godtossing/genesis-godtossing.bin godtossing/genesis-godtossing.bin
-- cp genesis-qanet-2017-06-13/genesis.info .
-- scp genesis-qanet-2017-06-13/nodes/* staging@cardano:~/staging/keys/

deploymentBuildTarget :: Deployment -> NixAttr
deploymentBuildTarget Nodes = "cardano-sl-static"
deploymentBuildTarget x     = error $ "'deploymentBuildTarget' has no idea what to build for " <> show x

build :: Options -> NixopsConfig -> Deployment -> IO ()
build o _c depl = do
  echo "Building derivation..."
  cmd o "nix-build" ["--max-jobs", "4", "--cores", "2", "-A", fromAttr $ deploymentBuildTarget depl]


-- * State management
--
-- Check if nodes are online and reboots them if they timeout
checkstatus :: Options -> NixopsConfig -> IO ()
checkstatus o c = do
  nodes <- getNodeNames o c
  parallelIO o $ fmap (rebootIfDown o c) nodes

rebootIfDown :: Options -> NixopsConfig -> NodeName -> IO ()
rebootIfDown o c (fromNodeName -> node) = do
  (x, _) <- nixops' o c "ssh" (node : ["-o", "ConnectTimeout=5", "echo", "-n"])
  case x of
    ExitSuccess -> return ()
    ExitFailure _ -> do
      TIO.putStrLn $ "Rebooting " <> node
      nixops o c "reboot" ["--include", node]

ssh  :: Options -> NixopsConfig -> [Text] -> NodeName -> IO ()
ssh o c = ssh' o c $ const $ return ()

ssh' :: Options -> NixopsConfig -> (Text -> IO ()) -> [Text] -> NodeName -> IO ()
ssh' o c f bin (fromNodeName -> node) = do
  let bin' = node: "--": bin
  (exitcode, out) <- nixops' o c "ssh" bin'
  f out
  case exitcode of
    ExitSuccess -> return ()
    ExitFailure code -> TIO.putStrLn $ "ssh cmd '" <> (T.intercalate " " bin') <> "' to '" <> node <> "' failed with " <> showT code

scpFromNode :: Options -> NixopsConfig -> NodeName -> Text -> Text -> IO ()
scpFromNode o c (fromNodeName -> node) from to = do
  (exitcode, _) <- nixops' o c "scp" ["--from", node, from, to]
  case exitcode of
    ExitSuccess -> return ()
    ExitFailure code -> TIO.putStrLn $ "scp from " <> node <> " failed with " <> showT code

sshForEach :: Options -> NixopsConfig -> [Text] -> IO ()
sshForEach o c command =
  nixops o c "ssh-for-each" ("--": command)

deployed'commit :: Options -> NixopsConfig -> NodeName -> IO ()
deployed'commit o c m = do
  ssh' o c (\r-> do
               case cut space r of
                 (_:path:_) -> do
                   drv <- incmd o "nix-store" ["--query", "--deriver", T.strip path]
                   pathExists <- testpath $ fromText $ T.strip drv
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
                 _    -> errorT $ "Unexpected output from 'pgrep -fa cardano-node': '" <> r <> "' / " <> showT (cut space r))
    ["pgrep", "-fa", "cardano-node"]
    m

wipeJournals :: Options -> NixopsConfig -> IO ()
wipeJournals o c@NixopsConfig{..} = do
  SimpleTopo cmap <- summariseTopology <$> readTopology cTopology
  echo "Wiping journals on cluster.."
  parallelIO o $ flip fmap (Map.keys cmap) $
    ssh' o c (const $ pure ()) ["bash -c", "'systemctl --quiet stop systemd-journald && rm -f /var/log/journal/*/* && systemctl start systemd-journald && sleep 1 && systemctl restart nix-daemon'"]
  echo "Done."

getJournals :: Options -> NixopsConfig -> IO ()
getJournals o c@NixopsConfig{..} = do
  SimpleTopo cmap <- summariseTopology <$> readTopology cTopology
  let nodes = Map.keys cmap
  echo "Dumping journald logs on cluster.."
  parallelIO o $ flip fmap nodes $
    ssh o c ["bash -c", "'rm -f log && journalctl -u cardano-node > log'"]
  echo "Obtaining dumped journals.."
  let outfiles  = format ("log-cardano-node-"%s%".journal") . fromNodeName <$> nodes
  parallelIO o $ flip fmap (zip nodes outfiles) $
    \(node, outfile) -> scpFromNode o c node "log" outfile
  timeStr <- T.pack . timePrint ISO8601_DateAndTime <$> dateCurrent
  let archive   = format ("journals-"%s%"-"%s%"-"%s%".tgz") (lowerShowT cEnvironment) cName timeStr
  printf ("Packing journals into "%s%"\n") archive
  cmd o "tar" (["czf", archive, "--force-local"] <> outfiles)
  cmd o "rm" $ "-f" : outfiles
  echo "Done."

confirmOrTerminate :: Text -> IO ()
confirmOrTerminate question = do
  echo $ unsafeTextToLine question <> "  Enter 'yes' to proceed:"
  reply <- readline
  unless (reply == Just "yes") $ do
    echo "User declined to proceed, exiting."
    exit $ ExitFailure 1

wipeNodeDBs :: Options -> NixopsConfig -> IO ()
wipeNodeDBs o c@NixopsConfig{..} = do
  confirmOrTerminate "Wipe node DBs on the entire cluster?"
  SimpleTopo cmap <- summariseTopology <$> readTopology cTopology
  parallelIO o $ flip fmap (Map.keys cmap) $
    ssh' o c (const $ pure ()) ["rm", "-rf", "/var/lib/cardano-node"]
  echo "Done."

updateNixops :: Options -> NixopsConfig -> IO ()
updateNixops o@Options{..} c@NixopsConfig{..} = do
  let (,) nixopsDir outLink = (,) "nixops" ("nixops-link" :: FilePath)
      configFile = flip fromMaybe oConfigFile $
        error "The 'update-nixops' subcommand requires the -c/--config option to 'iohk-ops'."
  preExists <- testpath nixopsDir
  unless preExists $ do
    errorT $ format ("The 'update-nixops' subcommand requires a '"%fp%"' subdirectory as input.") nixopsDir
  cd nixopsDir
  cmd o "nix-build" ["-A", "build.x86_64-linux", "--out-link", "../" <> format fp outLink, "release.nix"]
  sh $ do
    gitHeadRev <- inproc "git" ["rev-parse", "HEAD"] empty
    cd ".."
    nixopsStorePath <- inproc "readlink" [format fp outLink] empty
    liftIO $ printf ("Built nixops commit '"%s%"' is at '"%s%"', updating config '"%fp%"'\n")
      (lineToText gitHeadRev) (lineToText nixopsStorePath) configFile
    writeConfig (Just configFile) $ c { cNixops = Just $ Path.fromText $ lineToText nixopsStorePath <> "/bin/nixops" }
    -- Unfortunately, Turtle doesn't seem to provide anything of the form Shell a -> IO a,
    -- that would allow us to smuggle non-Text values out of a Shell monad.
  echo "Done."


-- * Functions for extracting information out of nixops info command
--
-- | Get all nodes in EC2 cluster
getNodes :: Options -> NixopsConfig -> IO [DeploymentInfo]
getNodes o c = do
  result <- (fmap . fmap) toNodesInfo $ info o c
  case result of
    Left str -> do
        TIO.putStrLn $ T.pack str
        return []
    Right vector -> return vector

getNodeNames :: Options -> NixopsConfig -> IO [NodeName]
getNodeNames o c = do
  nodes <- getNodes o c
  return $ fmap diName nodes

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


-- * Utils
showT :: Show a => a -> Text
showT = T.pack . show

readT :: Read a => Text -> a
readT = read . T.unpack

lowerShowT :: Show a => a -> Text
lowerShowT = T.toLower . T.pack . show

errorT :: Text -> a
errorT = error . T.unpack

jsonLowerStrip :: (Generic a, AE.GToJSON AE.Zero (Rep a)) => Int -> a -> AE.Value
jsonLowerStrip n = AE.genericToJSON $ AE.defaultOptions { AE.fieldLabelModifier = map toLower . drop n }
