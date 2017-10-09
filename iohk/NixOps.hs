{-# OPTIONS_GHC -Wall -Wno-orphans -Wno-missing-signatures -Wno-unticked-promoted-constructors -Wno-type-defaults #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ViewPatterns #-}

module NixOps where

import           Control.Arrow                    ((***))
import           Control.Exception                (throwIO)
import           Control.Lens                     ((<&>))
import           Control.Monad                    (forM_, mapM_)
import qualified Data.Aeson                    as AE
import           Data.Aeson                       ((.:), (.:?), (.=), (.!=))
import qualified Data.Aeson.Types              as AE
import           Data.Aeson.Encode.Pretty         (encodePretty)
import qualified Data.ByteString.Lazy          as BL
import           Data.ByteString.Lazy.Char8       (ByteString)
import qualified Data.ByteString.UTF8          as BU
import qualified Data.ByteString.Lazy.UTF8     as LBU
import           Data.Char                        (ord, toLower)
import           Data.Csv                         (decodeWith, FromRecord(..), FromField(..), HasHeader(..), defaultDecodeOptions, decDelimiter)
import           Data.Either
import           Data.Foldable                    (asum)
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
import           GHC.Stack
import           Prelude                   hiding (FilePath)
import           Safe                             (headMay)
import qualified System.IO                     as Sys
import qualified System.IO.Unsafe              as Sys
import qualified System.Posix.User             as Sys
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
defaultNixpkgs       = Nothing

defaultHold          = 1200 :: Seconds -- 20 minutes

explorerNode         = NodeName "explorer"

orgs :: [NodeOrg]
orgs                 = enumFromTo minBound maxBound
defaultOrg           = IOHK
accessKeyChain       = [ AccessKeyId $ showT org <> "accessKeyId"
                       | org <- orgs ]

simpleTopoFile       :: FilePath
simpleTopoFile       = "topology.nix"


-- * Flags & enumerables
--
every :: (Bounded a, Enum a) => [a]
every = enumFromTo minBound maxBound

class (Bounded a, Eq a) => Flag a where
  toBool :: a -> Bool
  toBool = (== enabled)
  fromBool :: Bool -> a
  fromBool x = if x then minBound else maxBound
  enabled, disabled :: a
  enabled  = minBound
  disabled = maxBound
  opposite :: a -> a
  opposite = fromBool . not . toBool


-- * Projects
--
data Project
  = CardanoSL
  | IOHKOps
  | Nixpkgs
  | Stack2nix
  | Nixops
  deriving (Bounded, Enum, Eq, Read, Show)

projectURL     :: Project -> URL
projectURL     CardanoSL       = "https://github.com/input-output-hk/cardano-sl"
projectURL     IOHKOps         = "https://github.com/input-output-hk/iohk-nixops"
projectURL     Nixpkgs         = "https://github.com/nixos/nixpkgs"
projectURL     Stack2nix       = "https://github.com/input-output-hk/stack2nix"
projectURL     Nixops          = "https://github.com/input-output-hk/nixops"

projectSrcFile :: Project -> FilePath
projectSrcFile CardanoSL       = "cardano-sl-src.json"
projectSrcFile Nixpkgs         = "nixpkgs-src.json"
projectSrcFile Stack2nix       = "stack2nix-src.json"
projectSrcFile IOHKOps         = error "Feeling self-referential?"
projectSrcFile Nixops          = error "No corresponding -src.json spec for 'nixops' yet."


-- * Primitive types
--
newtype AccessKeyId  = AccessKeyId  { fromAccessKeyId  :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype Arg          = Arg          { fromArg          :: Text   } deriving (IsString, Show)
newtype Branch       = Branch       { fromBranch       :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype ConfigurationKey = ConfigurationKey { fromConfigurationKey :: Text } deriving (IsString, Show)
newtype Commit       = Commit       { fromCommit       :: Text   } deriving (Eq, FromJSON, Generic, Show, IsString, ToJSON)
newtype Exec         = Exec         { fromExec         :: Text   } deriving (IsString, Show)
newtype EnvVar       = EnvVar       { fromEnvVar       :: Text   } deriving (IsString, Show)
newtype NixParam     = NixParam     { fromNixParam     :: Text   } deriving (FromJSON, Generic, Show, IsString, Eq, Ord, AE.ToJSONKey, AE.FromJSONKey)
newtype NixHash      = NixHash      { fromNixHash      :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype NixAttr      = NixAttr      { fromAttr         :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype NixopsCmd    = NixopsCmd    { fromCmd          :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype NixopsDepl   = NixopsDepl   { fromNixopsDepl   :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype Org          = Org          { fromOrg          :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype Region       = Region       { fromRegion       :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype Zone         = Zone         { fromZone         :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype URL          = URL          { fromURL          :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype FQDN         = FQDN         { fromFQDN         :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype IP           = IP           { getIP            :: Text   } deriving (Show, Generic, FromField)
newtype PortNo       = PortNo       { fromPortNo       :: Int    } deriving (FromJSON, Generic, Show, ToJSON)
newtype Username     = Username     { fromUsername     :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)

data BuildNixops      = BuildNixops      | DontBuildNixops    deriving (Bounded, Eq, Ord, Show); instance Flag BuildNixops
data Confirmed        = Confirmed        | Unconfirmed        deriving (Bounded, Eq, Ord, Show); instance Flag Confirmed
data Debug            = Debug            | NoDebug            deriving (Bounded, Eq, Ord, Show); instance Flag Debug
data Serialize        = Serialize        | DontSerialize      deriving (Bounded, Eq, Ord, Show); instance Flag Serialize
data Verbose          = Verbose          | NotVerbose         deriving (Bounded, Eq, Ord, Show); instance Flag Verbose
data ComponentCheck   = ComponentCheck   | NoComponentCheck   deriving (Bounded, Eq, Ord, Show); instance Flag ComponentCheck
data DoCommit         = DoCommit         | DontCommit         deriving (Bounded, Eq, Ord, Show); instance Flag DoCommit
data RebuildExplorer  = RebuildExplorer  | NoExplorerRebuild  deriving (Bounded, Eq, Ord, Show); instance Flag RebuildExplorer
data BuildOnly        = BuildOnly        | NoBuildOnly        deriving (Bounded, Eq, Ord, Show); instance Flag BuildOnly
data DryRun           = DryRun           | NoDryRun           deriving (Bounded, Eq, Ord, Show); instance Flag DryRun
data NewGenesis       = NewGenesis       | NoNewGenesis       deriving (Bounded, Eq, Ord, Show); instance Flag NewGenesis
data Validate         = Validate         | SkipValidation     deriving (Bounded, Eq, Ord, Show); instance Flag Validate
data PassCheck        = PassCheck        | DontPassCheck      deriving (Bounded, Eq, Ord, Show); instance Flag PassCheck
data WipeJournals     = WipeJournals     | KeepJournals       deriving (Bounded, Eq, Ord, Show); instance Flag WipeJournals
data WipeNodeDBs      = WipeNodeDBs      | KeepNodeDBs        deriving (Bounded, Eq, Ord, Show); instance Flag WipeNodeDBs
data ResumeFailed     = ResumeFailed     | DontResume         deriving (Bounded, Eq, Ord, Show); instance Flag ResumeFailed

deriving instance Eq NodeType
deriving instance Read NodeName
deriving instance AE.ToJSONKey NodeName

fromNodeName :: NodeName -> Text
fromNodeName (NodeName x) = x

-- | Sum to track assurance
data Confirmation = Confirm | Ask Text
  deriving (Eq, Read, Show)

confirmOrTerminate :: Confirmation -> IO ()
confirmOrTerminate  Confirm       = pure ()
confirmOrTerminate (Ask question) = do
  echo $ unsafeTextToLine question <> "  Enter 'yes' to proceed:"
  reply <- readline
  unless (reply == Just "yes") $ do
    echo "User declined to proceed, exiting."
    exit $ ExitFailure 1


-- * Some orphan instances..
--
instance FromJSON FilePath where parseJSON = AE.withText "filepath" $ \v -> pure $ fromText v
instance ToJSON   FilePath where toJSON    = AE.String . format fp
deriving instance Generic Seconds; instance FromJSON Seconds; instance ToJSON Seconds
deriving instance Generic Elapsed; instance FromJSON Elapsed; instance ToJSON Elapsed


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
instance ToJSON (NixSource Git) where
  toJSON GitSource{..} = AE.object
   [ "url"             .= fromURL gUrl
   , "rev"             .= fromCommit gRev
   , "sha256"          .= fromNixHash gSha256
   , "fetchSubmodules" .= lowerShowT gFetchSubmodules ]
instance FromJSON (NixSource Git) where
  parseJSON = AE.withObject "GitSource" $ \v -> GitSource
      <$> v .: "url"
      <*> v .: "rev"
      <*> v .: "sha256"
      <*> asum [ (v .: "fetchSubmodules")
               , readT . T.toTitle <$> (v .: "fetchSubmodules")]
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
  | NixAttrSet (Map.Map Text NixValue)
  | NixImport NixValue NixValue
  | NixFile FilePath
  | NixNull
  deriving (Generic, Show)
instance FromJSON NixValue
instance ToJSON NixValue

nixValueStr :: NixValue -> Text
nixValueStr (NixBool bool)      = T.toLower $ showT bool
nixValueStr (NixAttrSet attrs)  = ("{ " <>) . (<> " }") . T.concat
                                  $ [ k <> " = " <> nixValueStr v <> "; "
                                    | (k, v) <- Map.toList attrs ]
nixValueStr (NixImport f as)    = "import " <> nixValueStr f <> " " <>  nixValueStr as
nixValueStr (NixInt  int)       = showT int
nixValueStr (NixNull)           = "null"
nixValueStr (NixStr  str)       = "\"" <> str <>"\""          -- XXX: this is naive, as it doesn't do escaping
nixValueStr (NixFile f)         = let txt = format fp f
                                  in if T.isPrefixOf "/" txt
                                     then txt else ("./" <> txt)

nixArgCmdline :: NixParam -> NixValue -> [Text]
nixArgCmdline (NixParam name) x@(NixStr _) = ["--argstr", name, T.drop 1 $ nixValueStr x & T.dropEnd 1]
nixArgCmdline (NixParam name) x            = ["--arg",    name, nixValueStr x]


-- * Domain
--
data Deployment
  = Every
  | Explorer
  | Infra
  | Nodes
  | ReportServer
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


-- * Environment-specificity
--
data EnvSettings =
  EnvSettings
  { envDeployerUser      :: Username
  , envDefaultConfigurationKey :: ConfigurationKey
  , envDefaultConfig     :: FilePath
  , envDefaultGenesis    :: Maybe FilePath
  , envDefaultTopology   :: FilePath
  , envDeploymentFiles   :: [FileSpec]
  }

type FileSpec = (Deployment, Target, Text)

envSettings :: HasCallStack => Environment -> EnvSettings
envSettings env =
  let deplAgnosticFiles      = [ (Every,          All, "keypairs.nix")
                               , (Explorer,       All, "deployments/cardano-explorer.nix")
                               , (ReportServer,   All, "deployments/report-server.nix")
                               , (Nodes,          All, "deployments/cardano-nodes.nix")
                               , (Infra,          All, "deployments/infrastructure.nix")
                               , (Infra,          AWS, "deployments/infrastructure-target-aws.nix") ]
  in case env of
    Staging      -> EnvSettings
      { envDeployerUser      = "staging"
      , envDefaultConfigurationKey = "testnet_staging_full"
      , envDefaultConfig     = "staging-testnet.yaml"
      , envDefaultGenesis    = Just "genesis-staging.json"
      , envDefaultTopology   = "topology-staging.yaml"
      , envDeploymentFiles   = [ (Every,          All, "security-groups.nix")
                               , (Nodes,          All, "deployments/cardano-nodes-env-staging.nix")
                               , (Explorer,       All, "deployments/cardano-explorer-env-staging.nix")
                               , (ReportServer,   All, "deployments/report-server-env-staging.nix")
                               ] <> deplAgnosticFiles}
    Production  -> EnvSettings
      { envDeployerUser      = "live-production"
      , envDefaultConfigurationKey = "testnet_public_full"
      , envDefaultConfig     = "production-testnet.yaml"
      , envDefaultGenesis    = Just "genesis-mainnet.json"
      , envDefaultTopology   = "topology-production.yaml"
      , envDeploymentFiles   = [ (Nodes,          All, "security-groups.nix")
                               , (Explorer,       All, "security-groups.nix")
                               , (ReportServer,   All, "security-groups.nix")
                               , (Nodes,          All, "deployments/cardano-nodes-env-production.nix")
                               , (Explorer,       All, "deployments/cardano-explorer-env-production.nix")
                               , (ReportServer,   All, "deployments/report-server-env-production.nix")
                               , (Infra,          All, "deployments/infrastructure-env-production.nix")
                               ] <> deplAgnosticFiles}
    Development -> EnvSettings
      { envDeployerUser      = "staging"
      , envDefaultConfigurationKey = "devnet_shortep_full"
      , envDefaultConfig     = "config.yaml"
      , envDefaultGenesis    = Nothing
      , envDefaultTopology   = "topology-development.yaml"
      , envDeploymentFiles   = [ (Nodes,          All, "deployments/cardano-nodes-env-development.nix")
                               , (Explorer,       All, "deployments/cardano-explorer-env-development.nix")
                               , (ReportServer,   All, "deployments/report-server-env-development.nix")
                               ] <> deplAgnosticFiles}
    Any -> error "envSettings called with 'Any'"

selectDeployer :: Environment -> [Deployment] -> NodeName
selectDeployer Staging   delts | elem Nodes delts = "iohk"
                               | otherwise        = "cardano-deployer"
selectDeployer _ _                                = "cardano-deployer"

establishDeployerIP :: Options -> Maybe IP -> IO IP
establishDeployerIP o Nothing   = IP <$> incmd o "curl" ["--silent", fromURL awsPublicIPURL]
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
readTopology :: FilePath -> IO Topology
readTopology file = do
  eTopo <- liftIO $ YAML.decodeFileEither $ Path.encodeString file
  case eTopo of
    Right (topology :: Topology) -> pure topology
    Left err -> errorT $ format ("Failed to parse topology file: "%fp%": "%w) file err

newtype SimpleTopo
  =  SimpleTopo { fromSimpleTopo :: (Map.Map NodeName SimpleNode) }
  deriving (Generic, Show)
instance ToJSON SimpleTopo

data SimpleNode
  =  SimpleNode
     { snType     :: NodeType
     , snRegion   :: NodeRegion
     , snZone     :: NodeZone
     , snOrg      :: NodeOrg
     , snFQDN     :: FQDN
     , snPort     :: PortNo
     , snInPeers  :: [NodeName]                  -- ^ Incoming connection edges
     , snKademlia :: RunKademlia
     , snPublic   :: Bool
     } deriving (Generic, Show)
instance ToJSON SimpleNode where-- toJSON = jsonLowerStrip 2
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

-- | Dump intermediate core/relay info, as parametrised by the simplified topology file.
dumpTopologyNix :: NixopsConfig -> IO ()
dumpTopologyNix c@NixopsConfig{..} = sh $ do
  let nodeSpecExpr prefix =
        format ("with (import <nixpkgs> {}); "%s%" (import ./globals.nix { deployerIP = \"\"; environment = \""%s%"\"; genesis = "%s%"; topologyYaml = ./"%fp%"; systemStart = 0; "%s%" = \"-stub-\"; })")
               prefix (lowerShowT cEnvironment) (nixValueStr $ mDeplArg c $ NixParam "genesis") cTopology (T.intercalate " = \"-stub-\"; " $ fromAccessKeyId <$> accessKeyChain)
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




data Options = Options
  { oChdir            :: Maybe FilePath
  , oConfigFile       :: Maybe FilePath
  , oOnlyOn           :: Maybe NodeName
  , oDeployerIP       :: Maybe IP
  , oBuildNixops      :: BuildNixops
  , oConfirm          :: Confirmed
  , oDebug            :: Debug
  , oSerial           :: Serialize
  , oVerbose          :: Verbose
  , oNoComponentCheck :: ComponentCheck
  , oNixpkgs          :: Maybe FilePath
  } deriving Show

parserBranch :: Optional HelpMessage -> Parser Branch
parserBranch desc = Branch <$> argText "branch" desc

parserCommit :: Optional HelpMessage -> Parser Commit
parserCommit desc = Commit <$> argText "commit" desc

parserNodeLimit :: Parser (Maybe NodeName)
parserNodeLimit = optional $ NodeName <$> (optText "just-node" 'n' "Limit operation to the specified node")

flag :: Flag a => a -> ArgName -> Char -> Optional HelpMessage -> Parser a
flag effect long ch help = (\case
                               True  -> effect
                               False -> opposite effect) <$> switch long ch help

parserOptions :: Parser Options
parserOptions = Options
                <$> optional (optPath "chdir"     'C' "Run as if 'iohk-ops' was started in <path> instead of the current working directory.")
                <*> optional (optPath "config"    'c' "Configuration file")
                <*> (optional $ NodeName
                     <$>     (optText "on"        'o' "Limit operation to the specified node"))
                <*> (optional $ IP
                     <$>     (optText "deployer"  'd' "Directly specify IP address of the deployer: do not detect"))
                <*> flag BuildNixops      "build-nixops"       'b' "Use 'nixops' binary defined by 'default.nix', not config YAML."
                <*> flag Confirmed        "confirm"            'y' "Pass --confirm to nixops"
                <*> flag Debug            "debug"              'd' "Pass --debug to nixops"
                <*> flag Serialize        "serial"             's' "Disable parallelisation"
                <*> flag Verbose          "verbose"            'v' "Print all commands that are being run"
                <*> flag NoComponentCheck "no-component-check" 'p' "Disable deployment/*.nix component check"
                <*> (optional $ optPath "nixpkgs" 'i' "Set 'nixpkgs' revision")

nixpkgsCommitPath :: Commit -> Text
nixpkgsCommitPath = ("nixpkgs=" <>) . fromURL . nixpkgsNixosURL

nixopsCmdOptions :: Options -> NixopsConfig -> [Text]
nixopsCmdOptions Options{..} NixopsConfig{..} =
  ["--debug"   | oDebug   == Debug]   <>
  ["--confirm" | oConfirm == Confirmed] <>
  ["--show-trace"
  ,"--deployment", fromNixopsDepl cName
  ] <> fromMaybe [] ((["-I"] <>) . (:[]) . ("nixpkgs=" <>) . format fp <$> oNixpkgs)


-- | Before adding a field here, consider, whether the value in question
--   ought to be passed to Nix.
--   If so, the way to do it is to add a deployment argument (see DeplArgs),
--   which are smuggled across Nix border via --arg/--argstr.
data NixopsConfig = NixopsConfig
  { cName             :: NixopsDepl
  , cGenCmdline       :: Text
  , cNixpkgs          :: Maybe Commit
  , cNixops           :: FilePath
  , cTopology         :: FilePath
  , cEnvironment      :: Environment
  , cTarget           :: Target
  , cElements         :: [Deployment]
  , cFiles            :: [Text]
  , cDeplArgs         :: DeplArgs
  -- this isn't stored in the config file, but is, instead filled in during initialisation
  , topology          :: SimpleTopo
  } deriving (Generic, Show)
instance FromJSON NixopsConfig where
    parseJSON = AE.withObject "NixopsConfig" $ \v -> NixopsConfig
        <$> v .: "name"
        <*> v .:? "gen-cmdline"   .!= "--unknown--"
        <*> v .:? "nixpkgs"
        <*> v .:? "nixops"        .!= "nixops"
        <*> v .:? "topology"      .!= "topology-development.yaml"
        <*> v .: "environment"
        <*> v .: "target"
        <*> v .: "elements"
        <*> v .: "files"
        <*> v .: "args"
        <*> pure undefined -- this is filled in in readConfig
instance ToJSON Environment
instance ToJSON Target
instance ToJSON Deployment
instance ToJSON NixopsConfig where
  toJSON NixopsConfig{..} = AE.object
   [ "name"         .= fromNixopsDepl cName
   , "gen-cmdline"  .= cGenCmdline
   , "nixops"       .= cNixops
   , "topology"     .= cTopology
   , "environment"  .= showT cEnvironment
   , "target"       .= showT cTarget
   , "elements"     .= cElements
   , "files"        .= cFiles
   , "args"         .= cDeplArgs ]

deploymentFiles :: Environment -> Target -> [Deployment] -> [Text]
deploymentFiles cEnvironment cTarget cElements =
  nub $ concat (elementDeploymentFiles cEnvironment cTarget <$> cElements)

type DeplArgs = Map.Map NixParam NixValue

selectInitialConfigDeploymentArgs :: Options -> Maybe FilePath -> FilePath -> Environment -> [Deployment] -> Elapsed -> Maybe ConfigurationKey -> IO DeplArgs
selectInitialConfigDeploymentArgs _ mGenesis _ env delts (Elapsed systemStart) mConfigurationKey = do
    let EnvSettings{..}   = envSettings env
        akidDependentArgs = [ ( NixParam $ fromAccessKeyId akid
                              , NixStr . fromNodeName $ selectDeployer env delts)
                            | akid <- accessKeyChain ]
        configurationKey  = fromMaybe envDefaultConfigurationKey mConfigurationKey
    pure $ Map.fromList $
      akidDependentArgs
      <> [ ("systemStart",  NixInt $ fromIntegral systemStart)
         , ("genesis",      fromMaybe NixNull $ NixFile <$> mGenesis)
         , ("configurationKey", NixStr $ fromConfigurationKey configurationKey) ]

deplArg :: NixopsConfig -> NixParam -> NixValue -> NixValue
deplArg    NixopsConfig{..} k def = Map.lookup k cDeplArgs & fromMaybe def
  --(errorT $ format ("Deployment arguments don't hold a value for key '"%s%"'.") (showT k))

mDeplArg :: NixopsConfig -> NixParam -> NixValue
mDeplArg c p = deplArg c p NixNull

setDeplArg :: NixParam -> NixValue -> NixopsConfig -> NixopsConfig
setDeplArg p v c@NixopsConfig{..} = c { cDeplArgs = Map.insert p v cDeplArgs }

defaultDeplArgTo :: NixParam -> NixValue -> NixopsConfig -> NixopsConfig
defaultDeplArgTo p v c = setDeplArg p (deplArg c p v) c

-- | Interpret inputs into a NixopsConfig
mkNewConfig :: Options -> Text -> NixopsDepl -> Maybe FilePath -> Maybe FilePath -> Maybe FilePath -> Environment -> Target -> [Deployment] -> Elapsed -> Maybe ConfigurationKey -> IO NixopsConfig
mkNewConfig o cGenCmdline cName            mNixops    mGenesis mTopology cEnvironment cTarget cElements systemStart mConfigurationKey = do
  let EnvSettings{..} = envSettings                                            cEnvironment
      cNixops         = fromMaybe "nixops" mNixops
      cFiles          = deploymentFiles                                  cEnvironment cTarget cElements
      cTopology       = flip fromMaybe                         mTopology envDefaultTopology
      cNixpkgs        = defaultNixpkgs
  cDeplArgs    <- selectInitialConfigDeploymentArgs o mGenesis cTopology cEnvironment         cElements systemStart mConfigurationKey
  topology <- liftIO $ summariseTopology <$> readTopology cTopology
  pure NixopsConfig{..}

-- | Write the config file
writeConfig :: MonadIO m => Maybe FilePath -> NixopsConfig -> m FilePath
writeConfig mFp c@NixopsConfig{..} = do
  let configFilename = flip fromMaybe mFp $ envDefaultConfig $ envSettings cEnvironment
  liftIO $ writeTextFile configFilename $ T.pack $ BU.toString $ YAML.encode c
  pure configFilename

-- | Read back config, doing validation
readConfig :: MonadIO m => Options -> FilePath -> m NixopsConfig
readConfig Options{..} cf = do
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
  topo <- liftIO $ summariseTopology <$> readTopology cTopology
  pure c { topology = topo }


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
incmd :: Options -> Text -> [Text] -> IO Text

cmd   Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  Turtle.procs      bin args empty
cmd'  Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  Turtle.procStrict bin args empty
incmd Options{..} bin args = do
  when (toBool oVerbose) $ logCmd bin args
  inprocs bin args empty

gitHEADCommit :: Options -> IO Commit
gitHEADCommit o = Commit <$> incmd o "git" ["log", "-n1", "--pretty=format:%H"]


-- * Invoking nixops
--
iohkNixopsPath :: FilePath -> FilePath
iohkNixopsPath defaultNix =
  let storePath  = Sys.unsafePerformIO $ inprocs "nix-build" ["-A", "nixops", format fp defaultNix] $
                   (trace (T.unpack $ format ("INFO: using "%fp%" expression for its definition of 'nixops'") defaultNix) empty)
      nixopsPath = Path.fromText $ T.strip storePath <> "/bin/nixops"
  in trace (T.unpack $ format ("INFO: nixops is "%fp) nixopsPath) nixopsPath

nixops'' :: (Options -> Text -> [Text] -> IO b) -> Options -> NixopsConfig -> NixopsCmd -> [Arg] -> IO b
nixops'' executor o@Options{..} c@NixopsConfig{..} com args =
  executor o (format fp $ case oBuildNixops of
                            BuildNixops     -> iohkNixopsPath "default.nix"
                            DontBuildNixops -> cNixops)
  (fromCmd com : nixopsCmdOptions o c <> fmap fromArg args)

nixops' :: Options -> NixopsConfig -> NixopsCmd -> [Arg] -> IO (ExitCode, Text)
nixops  :: Options -> NixopsConfig -> NixopsCmd -> [Arg] -> IO ()
nixops' = nixops'' cmd'
nixops  = nixops'' cmd

nixopsMaybeLimitNodes :: Options -> [Arg]
nixopsMaybeLimitNodes (oOnlyOn -> maybeNode) = ((("--include":) . (:[]) . Arg . fromNodeName) <$> maybeNode & fromMaybe [])


-- * Deployment lifecycle
--
exists :: Options -> NixopsConfig -> IO Bool
exists o c@NixopsConfig{..} = do
  (code, _) <- nixops' o c "info" []
  pure $ code == ExitSuccess

create :: Options -> NixopsConfig -> IO ()
create o c@NixopsConfig{..} = do
  deplExists <- exists o c
  if deplExists
  then do
    printf ("Deployment already exists?: '"%s%"'") $ fromNixopsDepl cName
  else do
    printf ("Creating deployment "%s%"\n") $ fromNixopsDepl cName
    nixops o c "create" $ Arg <$> deploymentFiles cEnvironment cTarget cElements

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
  printf ("Syncing Nix->state for deployment "%s%"\n") $ fromNixopsDepl cName
  nixops o c "modify" $ Arg <$> cFiles

  printf ("Setting deployment arguments:\n")
  deplArgs <- computeFinalDeploymentArgs o c
  forM_ deplArgs $ \(name, val)
    -> printf ("  "%s%": "%s%"\n") (fromNixParam name) (nixValueStr val)
  nixops o c "set-args" $ Arg <$> (concat $ uncurry nixArgCmdline <$> deplArgs)

  printf ("Generating '"%fp%"' from '"%fp%"'..\n") simpleTopoFile cTopology
  preExisting <- testpath cTopology
  unless preExisting $
    die $ format ("Topology config '"%fp%"' doesn't exist.") cTopology
  simpleTopo <- summariseTopology <$> readTopology cTopology
  liftIO . writeTextFile simpleTopoFile . T.pack . LBU.toString $ encodePretty (fromSimpleTopo simpleTopo)
  when (toBool oDebug) $ dumpTopologyNix c

setenv :: Options -> EnvVar -> Text -> IO ()
setenv o@Options{..} (EnvVar k) v = do
  export k v
  when (oVerbose == Verbose) $
    cmd o "/bin/sh" ["-c", format ("echo 'export "%s%"='$"%s) k k]

deploy :: Options -> NixopsConfig -> DryRun -> BuildOnly -> PassCheck -> RebuildExplorer -> Maybe Seconds -> IO ()
deploy o@Options{..} c@NixopsConfig{..} dryrun buonly check reExplorer bumpSystemStartHeldBy = do
  when (elem Nodes cElements) $ do
     keyExists <- testfile "keys/key1.sk"
     unless keyExists $
       die "Deploying nodes, but 'keys/key1.sk' is absent."

  _ <- pure $ deplArg c (NixParam "configurationKey") $ errorT $
       format "'configurationKey' network argument missing from cluster config"
  when (dryrun /= DryRun && elem Explorer cElements && reExplorer /= NoExplorerRebuild) $ do
    cmd o "scripts/generate-explorer-frontend.sh" []
  when (dryrun /= DryRun && buonly /= BuildOnly) $ do
    deployerIP <- establishDeployerIP o oDeployerIP
    setenv o "SMART_GEN_IP" $ getIP deployerIP
  when (elem Nodes cElements) $
    setenv o "GC_INITIAL_HEAP_SIZE" (showT $ 15 * 1024*1024*1024) -- for 100 nodes it eats 12GB of ram *and* needs a bigger heap

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
    cmd o "git" (["add", format fp cFp])
    cmd o "git" ["commit", "-m", format ("Bump systemStart to "%s) timePretty]
  let mGenesis = mDeplArg c $ NixParam "genesis"
      configurationTmpl = "configuration.yaml.tmpl"
  genesisHash <- case mGenesis of
                   NixNull   -> pure "a000000000000000000000000000000000000000000000000000000000000000"
                   NixFile f -> do
                     let genesisTmpl = format (fp%".tmpl") f
                     cmd o "cp"  ["-f", genesisTmpl,       format fp f]
                     cmd o "sed" ["-i", format fp f,          "-e", format ("s/START_TIME_PLACEHOLDER/"%d%"/") (let Elapsed x = startE in x)]
                     incmd o "cardano-sl/scripts/js/genesis-hash.js" [format fp f]
                   x         -> errorT $ "'genesis' network argument must be either a NixFile or a NixNull (absent), was: " <> showT x
  cmd o "cp"  ["-f", configurationTmpl, "configuration.yaml"]
  cmd o "sed" ["-i", "configuration.yaml", "-e", format ("s/GENESIS_HASH_PLACEHOLDER/"%s%"/") (T.strip genesisHash)]

  modify o c'

  printf ("Deploying cluster "%s%"\n") $ fromNixopsDepl cName
  nixops o c' "deploy"
    $  [ "--max-concurrent-copy", "50", "-j", "4" ]
    ++ [ "--dry-run"       | dryrun == DryRun ]
    ++ [ "--build-only"    | buonly == BuildOnly ]
    ++ [ "--check"         | check  == PassCheck  ]
    ++ nixopsMaybeLimitNodes o
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
  deploy o c NoDryRun NoBuildOnly DontPassCheck RebuildExplorer (Just defaultHold)

deployValidate :: Options -> NixopsConfig -> RebuildExplorer -> IO ()
deployValidate o c _rebuildExplorerFrontend = do
  deploy o c DryRun NoBuildOnly DontPassCheck NoExplorerRebuild  Nothing

fromscratch :: Options -> NixopsConfig -> IO ()
fromscratch o c = do
  destroy o c
  delete o c
  create o c
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
prefetchURL :: Options -> Project -> Commit -> IO (NixHash, FilePath)
prefetchURL o proj rev = do
  let url = projectURL proj
  hashPath <- incmd o "nix-prefetch-url" ["--unpack", "--print-path", (fromURL $ url) <> "/archive/" <> fromCommit rev <> ".tar.gz"]
  let hashPath' = T.lines hashPath
  pure (NixHash (hashPath' !! 0), Path.fromText $ hashPath' !! 1)

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

runFakeKeys :: IO ()
runFakeKeys = do
  echo "Faking keys/key*.sk"
  testdir "keys"
    >>= flip unless (mkdir "keys")
  forM_ ([0..41]) $
    (\x-> do touch $ Turtle.fromText $ format ("keys/key"%d%".sk") x)
  echo "Minimum viable keyset complete."

ensureCardanoBranchCheckout :: Options -> Branch -> FilePath -> IO Commit
ensureCardanoBranchCheckout o branch dir = do
  preExisting <- testdir dir
  if preExisting
  then do
    cd dir
    printf ("Updating local checkout of 'cardano-sl' to the tip of 'origin/"%s%"'..\n") (fromBranch branch)
    cmd o "git" ["fetch", "origin"]
    cmd o "git" ["checkout", "-B", fromBranch branch, "origin/" <> fromBranch branch]
  else do
    printf ("Cloning 'cardano-sl' branch "%s%"\n") (fromBranch branch)
    cmd o "git" ["clone", "--branch", fromBranch branch, fromURL $ projectURL CardanoSL, "cardano-sl"]
    cd dir
  commit <- gitHEADCommit o
  cd ".."
  pure commit

-- | Generate genesis driving the tip of specified 'cardano-sl' branch.
generateOrInsertGenesis :: Options -> NixopsConfig -> Branch -> Maybe FilePath -> IO (Text, FilePath)
generateOrInsertGenesis o NixopsConfig{..} cardanoBranch preGenesis = do
  let cardanoSLDir     = "cardano-sl"
      genSuffix        = "tn"
      genesisName'     = "genesis-" <> genSuffix :: Text
      genesisTarball   = Path.fromText genesisName' <.> "tgz"
      (,) genM genN    = (,) (length . topoCores $ topology) 1200
      genFiles         = zip [ "genesis-core.bin"
                             , "genesis-godtossing.bin"
                             , "genesisCreation.log" ]
                         $   [ "core/genesis-core-"%s%".bin"
                             , "godtossing/genesis-godtossing-"%s%".bin"
                             , "genesis-info/"%s%".log" ]
                         <&> flip format genSuffix
  cardanoCommit <- ensureCardanoBranchCheckout o cardanoBranch cardanoSLDir
  printf ("Generating genesis using cardano-sl branch '"%s%"' (commit "%s%")\n  M:"%d%"\n  N:"%d%"\n")
    (fromBranch cardanoBranch) (fromCommit cardanoCommit) genM genN
  (genesisName,
   genesisPath,
   genesisCommitMsg) <- do
    case preGenesis of
      Nothing -> do
        echo "NEW genesis deployment requested"
        cd cardanoSLDir
        cmd o "rm" ["-rf", genesisName', format fp genesisTarball]
        cmd o "scripts/generate/genesis.sh"
          [ "--build-mode",        "nix"
          , "--install-as-suffix",  genSuffix
          , "--rich-keys",          showT genM
          , "--poor-keys",          showT genN
          , "--output-dir",         genesisName']
        pure (genesisName', cardanoSLDir </> genesisTarball,
              format ("Bump cardano: Regenerated genesis, M="%d%", N="%d%", cardano=") genM genN)
      Just genf -> do
        printf ("PREMADE genesis deployment requested: "%fp%"\n") genf
        existsp <- testfile genf
        unless existsp $
          errorT $ format ("PREMADE genesis file missing: "%fp%"\n") genf
        let stdGenesisName = dropExtension $ last $ splitDirectories genf
        echo "Installing genesis.."
        cmd o "rm" ["-rf", format ("./"%fp%"/"%s) cardanoSLDir genesisName', format fp genesisTarball]
        cmd o "tar" ["xaf", format fp genf, "-C", format fp cardanoSLDir]
        cd cardanoSLDir
        forM_ genFiles $
          \(from, to)-> cmd o "cp" ["-f", format fp $ stdGenesisName </> from, to]
        pure $ (format fp stdGenesisName, genf,
                format ("Bump cardano: Implanted genesis "%fp%", cardano=") stdGenesisName)

  printf ("Genesis NAME: "%s%"\n")  genesisName
  printf ("Genesis FILE: "%fp%"\n") genesisPath

  cmd o "git" (["add"] <> (snd <$> genFiles))
  cmd o "git" ["commit", "-m", format ("Regenerate genesis, M="%d%", N="%d) genM genN]
  echo "Genesis generated and committed, bumping 'iohk-ops'"
  cardanoGenesisCommit <- gitHEADCommit o
  printf ("Committed new genesis as 'cardano-sl' commit "%s%", pushing to 'origin'\n") (fromCommit cardanoGenesisCommit)
  cmd o "git" ["push", "origin"]
  cd ".."

  runSetRev o CardanoSL cardanoGenesisCommit (Just $ genesisCommitMsg <> (fromCommit cardanoCommit))
  cmd o "git" ["push", "origin"]
  echo "Don't forget to archive our new genesis:"
  cmd o "ls" ["-l", format fp genesisPath]
  pure (genesisName, genesisPath)

-- * Local phase of a full deployment
deployFullLocalPhase :: Options -> NixopsConfig -> Branch -> NewGenesis -> Maybe FilePath -> RebuildExplorer -> Validate -> IP -> IO ()
deployFullLocalPhase o@Options{..} c@NixopsConfig{..} cardanoBranchToDrive doGenesis preGenesis rebuildExplorerFrontend skipValidation deployerIP = do
  -- XXX: duplicated below
  let EnvSettings{..}   = envSettings cEnvironment
      cardanoSLDir      = "cardano-sl"
      deploymentAccount = fromUsername envDeployerUser <> "@" <> getIP deployerIP
      deploymentDir     = fromNixopsDepl cName
      deploymentSource  = format (s%":"%s%"/") deploymentAccount deploymentDir
  -- 0. Validate
  unless (skipValidation == SkipValidation) $ do
    echo "Validating 'iohk-ops' checkout.."
    create o c
    deployValidate o c rebuildExplorerFrontend
    -- XXX: re-enable this.. after figuring out how to use local 'iohk-ops'..
    -- cmd o "bash" ["scripts/travis.sh", "iohk-ops", format fp cNixops]
    -- cmd o "nix-build" ["--keep-failed", "jobsets/cardano.nix", "-A", "tests.simpleNode.x86_64-linux", "--show-trace"]
  -- 1. Bump Cardano
  branchHEAD <- ensureCardanoBranchCheckout o cardanoBranchToDrive cardanoSLDir
  GitSource{..} <- readSource gitSource CardanoSL
  unless (branchHEAD == gRev) $ do
    runSetRev o CardanoSL branchHEAD (Just $ format ("Bump cardano-sl to:  "%s) (fromCommit branchHEAD))
  -- 2. Record first bump and trigger CI
  printf ("Pushing local 'iohk-ops' commit into 'origin'..\n")
  cmd o "git" ["push", "origin"]
  -- 3. Genesis
  when (doGenesis == NewGenesis || isJust preGenesis) $ do
    case (doGenesis, preGenesis) of
      (NewGenesis, Just _) -> error "Asked to both regenerate and use supplied genesis: these options are exclusive."
      _                    -> pure ()
    (genesisName,
     genesisPath) <- generateOrInsertGenesis o c cardanoBranchToDrive preGenesis
    let richKeys = length . topoCores $ topology
    printf ("Updating deployer genesis: "%s%"\n") deploymentSource
    echo "  -- removing old genesis"
    cmd o "ssh" [ deploymentAccount, "bash", "-c", format ("'rm -rf ./genesis-tn-*'")]
    echo "  -- uploading generated genesis archive"
    cmd o "scp" [ format fp genesisPath, deploymentSource ]
    echo "  -- unpacking genesis archive"
    cmd o "ssh" [ deploymentAccount, "tar", "xaf", deploymentDir <> "/" <> genesisName <> ".tgz", "-C", deploymentDir ]
    echo "  -- removing old rich keys"
    cmd o "ssh" [ deploymentAccount, "bash", "-c"
                , format ("'cd "%s%" && rm -f ./keys/*'") deploymentDir]
    echo "  -- installing genesis rich keys"
    cmd o "ssh" [ deploymentAccount, "bash", "-c"
                , format ("'cd "%s%" && for x in {1.."%d%"}; do cp "%s%"/keys-testnet/rich/testnet$x.key keys/key$((x-1)).sk; done'")
                  deploymentDir richKeys genesisName]
  -- 4. Wait for CI (either after first or second bump)
  opsCommit <- gitHEADCommit o
  echo ""
  echo "CI status:  https://hydra.iohk.io/jobset/serokell/iohk-nixops-staging#tabs-evaluations"
  printf ("\nPress 'Enter' when CI has built the evaluation for 'iohk-ops' commit "%s%"\n") (fromCommit opsCommit)
  void readline

deployFullDeployerPhase :: Options -> NixopsConfig -> Seconds -> WipeNodeDBs -> RebuildExplorer -> IO ()
deployFullDeployerPhase o c@NixopsConfig{..} bumpHeldBy doWipeNodeDBs reExplorer = do
  -- 0. If we have nixpkgs commit set in the config, propagate
  nixpkgsPath <- case cNixpkgs of
    Nothing -> pure Nothing
    Just commit -> do
      (_, storePath) <- prefetchURL o Nixpkgs commit
      pure $ Just storePath
  let options' = o { oNixpkgs = nixpkgsPath }

  -- 6. --dry-run
  deploy options' c DryRun BuildOnly DontPassCheck reExplorer Nothing

  -- 7. cleanup
  stop o c
  wipeJournals o c
  when (doWipeNodeDBs == WipeNodeDBs) $
    wipeNodeDBs o c Confirm

  -- 8. for real
  deploy options' c NoDryRun NoBuildOnly PassCheck NoExplorerRebuild (Just bumpHeldBy)

runningOnDeployer :: IO Bool
runningOnDeployer = flip elem ["staging", "live-production"] <$> Sys.getLoginName

-- | Deploy the specified 'cardano-sl' branch, possibly with new genesis.
deployFull :: Options -> NixopsConfig -> Branch -> Seconds -> NewGenesis -> Maybe FilePath -> WipeNodeDBs -> RebuildExplorer -> Validate -> ResumeFailed -> IO ()
deployFull o@Options{..} c@NixopsConfig{..} cardanoBranchToDrive bumpHeldBy newGenesis preGenesis wipeDBs reExplorer validate resume = do
  deployerIP <- establishDeployerIP o oDeployerIP
  let EnvSettings{..}   = envSettings cEnvironment
      deploymentAccount = fromUsername envDeployerUser <> "@" <> getIP deployerIP
      deploymentDir     = fromNixopsDepl cName
      deploymentSource  = format (s%":"%s%"/") deploymentAccount deploymentDir
      doWipe            = newGenesis == NewGenesis || wipeDBs == WipeNodeDBs

  onDeployer <- runningOnDeployer
  when onDeployer $ error "The 'iohk-ops deploy' subcommand is designed to be run from a developer machine."

  unless (resume == ResumeFailed) $
    deployFullLocalPhase o c cardanoBranchToDrive newGenesis preGenesis reExplorer validate deployerIP

  -- 5. Remote, on-deployer phase
  opsCommit <- gitHEADCommit o

  printf ("Updating deployment source: "%s%"\n") deploymentSource
  cmd o "ssh"   [ deploymentAccount, "git", "-C", deploymentDir, "fetch", "origin" ]
  cmd o "ssh"   [ deploymentAccount, "git", "-C", deploymentDir, "reset", "--hard", fromCommit opsCommit ]
  cmd o "ssh" $ [ "--", deploymentAccount, "bash",  "-c",
                  format ("'echo && \
                          \ cd ~/"%s%" && \
                          \ pwd && \
                          \ $(nix-build -A iohk-ops default.nix)/bin/iohk-ops \
                             \ --config "%fp%" \
                             \ deploy-full-deployer-phase \
                             \ --bump-system-start-held-by "%d%" "%s%" "%s%"'")
                  deploymentDir (fromJust oConfigFile) (bumpHeldBy `div` 60)
                  (if doWipe                        then "--wipe-node-dbs" else "")
                  (if reExplorer == RebuildExplorer then "" else "--no-explorer-rebuild")
                ]

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

sshForEach :: Options -> NixopsConfig -> [Text] -> IO ()
sshForEach o c command =
  nixops o c "ssh-for-each" $ Arg <$> "--": command

deployedCommit :: Options -> NixopsConfig -> NodeName -> IO ()
deployedCommit o c m = do
  ssh' o c "pgrep" ["-fa", "cardano-node"] m $
    \r-> do
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
        _    -> errorT $ "Unexpected output from 'pgrep -fa cardano-node': '" <> r <> "' / " <> showT (cut space r)


startForeground :: Options -> NixopsConfig -> NodeName -> IO ()
startForeground o c node =
  ssh' o c "bash" [ "-c", "'systemctl show cardano-node --property=ExecStart | sed -e \"s/.*path=\\([^ ]*\\) .*/\\1/\" | xargs grep \"^exec \" | cut -d\" \" -f2-'"]
  node $ \unitStartCmd ->
    printf ("Starting Cardano in foreground;  Command line:\n  "%s%"\n") unitStartCmd >>
    ssh o c "bash" ["-c", Arg $ "'sudo -u cardano-node " <> unitStartCmd <> "'"] node

stop :: Options -> NixopsConfig -> IO ()
stop o c = echo "Stopping nodes..."
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

wipeJournals :: Options -> NixopsConfig -> IO ()
wipeJournals o c@NixopsConfig{..} = do
  echo "Wiping journals on cluster.."
  parallelSSH o c "bash"
    ["-c", "'systemctl --quiet stop systemd-journald && rm -f /var/log/journal/*/* && systemctl start systemd-journald && sleep 1 && systemctl restart nix-daemon'"]
  echo "Done."

getJournals :: Options -> NixopsConfig -> IO ()
getJournals o c@NixopsConfig{..} = do
  let nodes = nodeNames o c

  echo "Dumping journald logs on cluster.."
  parallelSSH o c "bash"
    ["-c", "'rm -f log && journalctl -u cardano-node > log'"]

  echo "Obtaining dumped journals.."
  let outfiles  = format ("log-cardano-node-"%s%".journal") . fromNodeName <$> nodes
  parallelIO' o c (flip zip outfiles) $
    \(node, outfile) -> scpFromNode o c node "log" outfile
  timeStr <- T.replace ":" "_" . T.pack . timePrint ISO8601_DateAndTime <$> dateCurrent

  let archive   = format ("journals-"%s%"-"%s%"-"%s%".tgz") (lowerShowT cEnvironment) (fromNixopsDepl cName) timeStr
  printf ("Packing journals into "%s%"\n") archive
  cmd o "tar" (["czf", archive] <> outfiles)
  cmd o "rm" $ "-f" : outfiles
  echo "Done."

wipeNodeDBs :: Options -> NixopsConfig -> Confirmation -> IO ()
wipeNodeDBs o c@NixopsConfig{..} confirmation = do
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
