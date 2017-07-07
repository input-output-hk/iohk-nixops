{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ViewPatterns #-}

module NixOps where

import Prelude hiding (FilePath)
import           Control.Exception (throwIO)
import qualified Data.Aeson                    as AE
import           Data.Aeson                       ((.:), (.=))
import qualified Data.ByteString.Lazy          as BL
import qualified Data.ByteString.UTF8          as BUTF8
import Data.Char (ord)
import qualified Data.Yaml                     as YAML
import Data.Yaml (FromJSON(..), ToJSON(..))
import           Data.Maybe
import qualified Data.Map                      as Map
import Data.Monoid ((<>))
import           Data.Optional (Optional)
import           Data.List                        (sort)
import qualified Data.Set                      as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Text.Lazy (fromStrict)
import Data.Text.Lazy.Encoding (encodeUtf8)
import Data.Csv (decodeWith, FromRecord(..), FromField(..), HasHeader(..), defaultDecodeOptions, decDelimiter)
import qualified Data.Vector as V
import Data.ByteString.Lazy.Char8 (ByteString, pack)
import qualified Filesystem.Path.CurrentOS     as Path
import GHC.Generics
import Safe (headMay)
import           Text.Read                        (readMaybe)
import Turtle hiding (procs)
import qualified Turtle as Turtle


-- * Constants
--
iohkNixopsURL, cardanoSlURL, cardanoSlExplorerURL, stack2NixURL, awsPublicIPURL :: URL
iohkNixopsURL        = "https://github.com/input-output-hk/iohk-nixops.git"
cardanoSlURL         = "https://github.com/input-output-hk/cardano-sl.git"
cardanoSlExplorerURL = "https://github.com/input-output-hk/cardano-sl-explorer.git"
stack2NixURL         = "https://github.com/input-output-hk/stack2nix.git"
awsPublicIPURL       = "http://169.254.169.254/latest/meta-data/public-ipv4"

defaultEnvironment = Development
defaultTarget      = AWS
defaultNodeLimit   = 14


-- * Primitive types
--
newtype Branch    = Branch    { fromBranch  :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype Commit    = Commit    { fromCommit  :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype NixParam  = NixParam  { fromNixParam :: Text } deriving (FromJSON, Generic, Show, IsString, Eq, Ord, AE.ToJSONKey, AE.FromJSONKey)
newtype Machine   = Machine   { fromMachine :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype NixHash   = NixHash   { fromNixHash :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype NixAttr   = NixAttr   { fromAttr    :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype NixopsCmd = NixopsCmd { fromCmd     :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype Region    = Region    { fromRegion  :: Text } deriving (FromJSON, Generic, Show, IsString)
newtype URL       = URL       { fromURL     :: Text } deriving (FromJSON, Generic, Show, IsString)


-- * A bit of Nix types
--
-- | The output of 'nix-prefetch-git'
data NixGitSource
  = NixGitSource
  { url             :: URL
  , rev             :: Commit
  , sha256          :: NixHash
  , fetchSubmodules :: Bool
  } deriving (Generic, Show)
instance FromJSON NixGitSource

-- | The set of first-class types present in Nix
data NixValue
  = NixBool Bool
  | NixInt  Integer
  | NixStr  Text
  deriving (Generic, Show)
instance FromJSON NixValue
instance ToJSON NixValue

nixArgCmdline :: NixParam -> NixValue -> [Text]
nixArgCmdline (NixParam name) (NixBool bool) = ["--arg",    name, T.toLower $ showT bool]
nixArgCmdline (NixParam name) (NixInt int)   = ["--arg",    name, showT int]
nixArgCmdline (NixParam name) (NixStr str)   = ["--argstr", name, str]


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
  deriving (Eq, Generic, Read, Show)
instance FromJSON Environment

data Target
  = All               -- ^ Wildcard or unspecified, depending on context.
  | AWS
  deriving (Eq, Generic, Read, Show)
instance FromJSON Target

allDeployments :: [Deployment]
allDeployments = enumFromTo minBound maxBound

envConfigFilename :: IsString s => Environment -> s
envConfigFilename Any           = "config.yaml"
envConfigFilename Development   = "config.yaml"
envConfigFilename Staging       = "staging.yaml"
envConfigFilename Production    = "production.yaml"

selectDeployer :: Environment -> [Deployment] -> Machine
selectDeployer _ depl | elem Infra depl = "cardano-deployer"
selectDeployer _ _                       = "iohk"

type DeplArgs = Map.Map NixParam NixValue

selectDeploymentArgs :: Environment -> [Deployment] -> Integer -> DeplArgs
selectDeploymentArgs env delts limit = Map.fromList
  [ ("accessKeyId"
    , NixStr . fromMachine $ selectDeployer env delts)
  , ("nodeLimit"
    , NixInt limit ) ]


-- * Deployment structure
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

nixopsCmdOptions :: Options -> NixopsConfig -> [Text]
nixopsCmdOptions Options{..} NixopsConfig{..} =
  ["--debug"   | oDebug]   <>
  ["--confirm" | oConfirm] <>
  ["--show-trace"
  ,"--deployment", cName ]


data NixopsConfig = NixopsConfig
  { cName             :: Text
  , cEnvironment      :: Environment
  , cTarget           :: Target
  , cElements         :: [Deployment]
  , cFiles            :: [Text]
  , cDeplArgs         :: DeplArgs
  } deriving (Generic, Show)
instance FromJSON NixopsConfig where
    parseJSON = AE.withObject "NixopsConfig" $ \v -> NixopsConfig
        <$> v .: "name"
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
   , "environment" .= showT cEnvironment
   , "target"      .= showT cTarget
   , "elements"    .= cElements
   , "files"       .= cFiles
   , "args"        .= cDeplArgs ]

deploymentFiles :: Environment -> Target -> [Deployment] -> [Text]
deploymentFiles cEnvironment cTarget cElements =
  "deployments/keypairs.nix":
  concat (elementDeploymentFiles cEnvironment cTarget <$> cElements)

-- | Interpret inputs into a NixopsConfig
mkConfig :: Branch -> Environment -> Target -> [Deployment] -> Integer -> NixopsConfig
mkConfig (Branch cName) cEnvironment cTarget cElements nodeLimit =
  let cFiles    = deploymentFiles cEnvironment cTarget cElements
      cDeplArgs = selectDeploymentArgs cEnvironment cElements nodeLimit
  in NixopsConfig{..}

-- | Write the config file
writeConfig :: MonadIO m => Maybe FilePath -> NixopsConfig -> m FilePath
writeConfig mFp c@NixopsConfig{..} = do
  let configFilename = flip fromMaybe mFp $ envConfigFilename cEnvironment
  liftIO $ writeTextFile configFilename $ T.pack $ BUTF8.toString $ YAML.encode c
  pure configFilename
  
-- | Read back config, doing validation
readConfig :: MonadIO m => FilePath -> m NixopsConfig
readConfig cf = do
  cfParse <- liftIO $ YAML.decodeFileEither $ Path.encodeString $ cf
  let c@NixopsConfig{..}
        = case cfParse of
            Right c -> c
            Left  e -> error $ T.unpack $ format ("Failed to parse config file "%fp%": "%s)
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

inprocs :: MonadIO m => Text -> [Text] -> Shell Line -> m Text
inprocs cmd args input = do
  (exitCode, stdout) <- liftIO $ procStrict cmd args input
  unless (exitCode == ExitSuccess) $
    liftIO (throwIO (ProcFailed cmd args exitCode))
  pure stdout 

cmd   :: Options -> Text -> [Text] -> IO ()
cmd'  :: Options -> Text -> [Text] -> IO (ExitCode, Text)
incmd :: Options -> Text -> [Text] -> IO Text

logCmd  cmd args =
  printf ("-- "%s%"\n") $ T.intercalate " " $ cmd:args
  
cmd   Options{..} cmd args = do
  when oVerbose $ logCmd cmd args
  Turtle.procs      cmd args empty
cmd'  Options{..} cmd args = do
  when oVerbose $ logCmd cmd args
  Turtle.procStrict cmd args empty
incmd Options{..} cmd args = do
  when oVerbose $ logCmd cmd args
  inprocs cmd args empty

nixops  :: Options -> NixopsConfig -> NixopsCmd -> [Text] -> IO ()
nixops' :: Options -> NixopsConfig -> NixopsCmd -> [Text] -> IO (ExitCode, Text)

nixops  o c (NixopsCmd com) args = cmd  o "nixops" (com : nixopsCmdOptions o c <> args)
nixops' o c (NixopsCmd com) args = cmd' o "nixops" (com : nixopsCmdOptions o c <> args)


-- * Deployment lifecycle
--
exists :: Options -> NixopsConfig -> IO Bool
exists o c@NixopsConfig{..} = do
  (code, _) <- nixops' o c "info" []
  pure $ code == ExitSuccess

create :: Options -> NixopsConfig -> IO ()
create o c@NixopsConfig{..} = do
  clusterExists <- exists o c
  when clusterExists $
    die $ format ("Cluster already exists?: '"%s%"'") cName
  printf ("Creating cluster "%s%"\n") cName
  nixops o c "create" $ deploymentFiles cEnvironment cTarget cElements

modify :: Options -> NixopsConfig -> IO ()
modify o c@NixopsConfig{..} = do
  printf ("Syncing Nix->state for cluster "%s%"\n") cName
  nixops o c "modify" $ deploymentFiles cEnvironment cTarget cElements

deploy :: Options -> NixopsConfig -> Bool -> IO ()
deploy o c@NixopsConfig{..} evonly = do
  when (elem Nodes cElements) $ do
     keyExists <- testfile "keys/key1.sk"
     unless keyExists $
       die "Deploying nodes, but 'keys/key1.sk' is absent."

  printf ("Deploying cluster "%s%"\n") cName
  when (not evonly) $ do
    when (elem Nodes cElements) $ do
      export "GC_INITIAL_HEAP_SIZE" (showT $ 8 * 1024*1024*1024) -- for 100 nodes it eats 12GB of ram *and* needs a bigger heap
    export "SMART_GEN_IP"     =<< incmd o "curl" ["--silent", fromURL awsPublicIPURL]
    when (elem Explorer cElements) $ do
      cmd o "scripts/generate-explorer-frontend.sh" []

  nixops o c "set-args" $ concat $ uncurry nixArgCmdline <$> Map.toList cDeplArgs

  nixops o c "modify" $ deploymentFiles cEnvironment cTarget cElements

  nixops o c "deploy" $
    [ "--max-concurrent-copy", "50", "-j", "4" ]
    ++ [ "--evaluate-only" | evonly ]
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
  deploy o c False


-- * Building
--
generateGenesis :: Options -> NixopsConfig -> IO ()
generateGenesis o c = do
  let cardanoSLSrcSpecFile = "cardano-sl-src.json"
      cardanoSLDir         = "cardano-sl"
  bs    <- BL.readFile cardanoSLSrcSpecFile
  let NixGitSource{..} = flip fromMaybe (AE.decode bs) $
                         errorT $ format ("Version spec for 'cardano-sl' doesn't parse as NixGitSource: "%s) (T.pack cardanoSLSrcSpecFile)
  printf ("Generating genesis using cardano-sl commit "%s%"\n") $ fromCommit rev
  exists <- testpath cardanoSLDir
  unless exists $
    cmd o "git" ["clone", fromURL cardanoSlURL, "cardano-sl"]
  cd "cardano-sl"
  cmd o "git" ["fetch"]
  cmd o "git" ["reset", "--hard", fromCommit rev]
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
build o c d = do
  echo "Building derivation..."
  cmd o "nix-build" ["--max-jobs", "4", "--cores", "2", "-A", fromAttr $ deploymentBuildTarget d]


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
ssh' o c f cmd (fromNodeName -> node) = do
  let cmd' = node: "--": cmd
  (exitcode, output) <- nixops' o c "ssh" cmd'
  f output
  case exitcode of
    ExitSuccess -> return ()
    ExitFailure code -> TIO.putStrLn $ "ssh cmd '" <> (T.intercalate " " cmd') <> "' to '" <> node <> "' failed with " <> showT code

scpFromNode :: Options -> NixopsConfig -> NodeName -> Text -> Text -> IO ()
scpFromNode o c (fromNodeName -> node) from to = do
  (exitcode, output) <- nixops' o c "scp" ["--from", node, from, to]
  case exitcode of
    ExitSuccess -> return ()
    ExitFailure code -> TIO.putStrLn $ "scp from " <> node <> " failed with " <> showT code

sshForEach :: Options -> NixopsConfig -> [Text] -> IO ()
sshForEach o c cmd = 
  nixops o c "ssh-for-each" ("--": cmd)


-- * Functions for extracting information out of nixops info command
--
newtype IP = IP { getIP :: Text }
   deriving (Show, Generic, FromField)
newtype NodeName = NodeName { fromNodeName :: Text }
   deriving (Show, Generic, FromField)

-- | Get all nodes in EC2 cluster
getNodes :: Options -> NixopsConfig -> IO [DeploymentInfo]
getNodes o c = do
  result <- (fmap . fmap) toNodesInfo $ info o c
  case result of
    Left s -> do
        TIO.putStrLn $ T.pack s
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


-- * Unused
nixpkgsBaseURL = "https://github.com/NixOS/nixpkgs/archive/"

nixpkgsURL :: Commit -> URL
nixpkgsURL = URL . (\c-> nixpkgsBaseURL <> c <> ".tar.gz") . fromCommit


-- * Utils
showT :: Show a => a -> Text
showT = T.pack . show

errorT :: Text -> a
errorT = error . T.unpack
