{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults #-}

module Types
  ( module Types
  , module Arch
  ) where

import           Prelude               hiding (FilePath)
import qualified Data.Aeson            as AE
import qualified Data.ByteString.Char8 as BS.C8
import           Data.Csv              (FromField (..))
import qualified GHC.Generics          as G
import qualified Data.Map.Strict       as Map
import           Data.String
import           Data.Text
import           Data.Word             (Word16)
import           Data.Yaml             (FromJSON (..), ToJSON (..))
import           GHC.Generics          hiding (from, to)
import qualified Turtle                        as Turtle

import Arch

-- * Elementary types
--
newtype AccessKeyId  = AccessKeyId  { fromAccessKeyId  :: Text   } deriving (FromJSON, Generic, Show, IsString, ToJSON)
newtype Arg          = Arg          { fromArg          :: Text   } deriving (IsString, Show)
newtype Branch       = Branch       { fromBranch       :: Text   } deriving (FromJSON, Generic, Show, IsString)
newtype ConfigurationKey = ConfigurationKey { fromConfigurationKey :: Text } deriving (IsString, Show)
newtype Commit       = Commit       { fromCommit       :: Text   } deriving (Eq, FromJSON, Generic, Show, IsString, ToJSON)
newtype Exec         = Exec         { fromExec         :: Text   } deriving (IsString, Show)
newtype EnvVar       = EnvVar       { fromEnvVar       :: Text   } deriving (IsString, Show)
newtype JournaldTimeSpec = JournaldTimeSpec { fromJournaldTimeSpec :: Text   } deriving (Show, IsString)
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
newtype ApplicationVersion = ApplicationVersion { getApplicationVersion :: Text } deriving (FromJSON, IsString, Show, Eq, Generic, ToJSON)

-- * Flags
--
data BuildNixops      = BuildNixops      | DontBuildNixops    deriving (Bounded, Eq, Ord, Show); instance Flag BuildNixops
data Confirmed        = Confirmed        | Unconfirmed        deriving (Bounded, Eq, Ord, Show); instance Flag Confirmed
data Debug            = Debug            | NoDebug            deriving (Bounded, Eq, Ord, Show); instance Flag Debug
data Serialize        = Serialize        | DontSerialize      deriving (Bounded, Eq, Ord, Show); instance Flag Serialize
data Verbose          = Verbose          | NotVerbose         deriving (Bounded, Eq, Ord, Show); instance Flag Verbose
data ComponentCheck   = ComponentCheck   | NoComponentCheck   deriving (Bounded, Eq, Ord, Show); instance Flag ComponentCheck
data DoCommit         = DoCommit         | DontCommit         deriving (Bounded, Eq, Ord, Show); instance Flag DoCommit
data BuildOnly        = BuildOnly        | NoBuildOnly        deriving (Bounded, Eq, Ord, Show); instance Flag BuildOnly
data DryRun           = DryRun           | NoDryRun           deriving (Bounded, Eq, Ord, Show); instance Flag DryRun
data Validate         = Validate         | SkipValidation     deriving (Bounded, Eq, Ord, Show); instance Flag Validate
data PassCheck        = PassCheck        | DontPassCheck      deriving (Bounded, Eq, Ord, Show); instance Flag PassCheck
data WipeJournals     = WipeJournals     | KeepJournals       deriving (Bounded, Eq, Ord, Show); instance Flag WipeJournals
data WipeNodeDBs      = WipeNodeDBs      | KeepNodeDBs        deriving (Bounded, Eq, Ord, Show); instance Flag WipeNodeDBs
data ResumeFailed     = ResumeFailed     | DontResume         deriving (Bounded, Eq, Ord, Show); instance Flag ResumeFailed
data GenerateKeys     = GenerateKeys     | DontGenerateKeys   deriving (Bounded, Eq, Ord, Show); instance Flag GenerateKeys

deriving instance Eq NodeType
deriving instance Read NodeName
deriving instance AE.ToJSONKey NodeName

fromNodeName :: NodeName -> Text
fromNodeName (NodeName x) = x

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

-- * Topology.hs
--
data NodeAddr a =
    NodeAddrExact BS.C8.ByteString (Maybe Word16)
  | NodeAddrDNS a (Maybe Word16)
  deriving (Show)

newtype NodeName = NodeName Text deriving (Show, Ord, Eq, IsString)

instance FromJSON NodeName where
  parseJSON = fmap NodeName . parseJSON

data NodeOrg = IOHK | CF | Emurgo
    deriving (Bounded, Eq, Enum, Generic, Read, Show)

instance FromJSON NodeOrg
instance ToJSON NodeOrg

data NodeType = NodeCore | NodeRelay | NodeEdge
  deriving (Show)

newtype NodeRegion = NodeRegion Text
    deriving (Show, Ord, Eq, IsString)

instance FromJSON NodeType where
  parseJSON = AE.withText "NodeType" $ \typ -> do
      case unpack typ of
        "core"     -> return NodeCore
        "edge"     -> return NodeEdge
        "relay"    -> return NodeRelay
        _otherwise -> fail $ "Invalid NodeType " ++ show typ


-- * Domain
--
data Deployment
  = Every
  | Explorer
  | Faucet
  | Infra
  | Nodes
  | ReportServer
  deriving (Bounded, Eq, Enum, Generic, Read, Show)
instance FromJSON Deployment

data Environment
  = Any               -- ^ Wildcard or unspecified, depending on context.
  | Benchmark
  | Production
  | Staging
  | Testnet
  | Development
  deriving (Bounded, Eq, Enum, Generic, Read, Show)
instance FromJSON Environment

data Target
  = All               -- ^ Wildcard or unspecified, depending on context.
  | AWS
  deriving (Bounded, Eq, Enum, Generic, Read, Show)
instance FromJSON Target

-- * Nix

data SourceKind = Git | Github

data NixSource (a :: SourceKind) where
  -- | The output of 'nix-prefetch-git'
  GitSource ::
    { gUrl             :: URL
    , gRev             :: Commit
    , gSha256          :: NixHash
    , gFetchSubmodules :: Bool
    } -> NixSource 'Git
  GithubSource ::
    { ghOwner           :: Text
    , ghRepo            :: Text
    , ghRev             :: Commit
    , ghSha256          :: NixHash
    } -> NixSource 'Github

data NixValue
  = NixBool Bool
  | NixInt  Integer
  | NixStr  Text
  | NixAttrSet (Map.Map Text NixValue)
  | NixImport NixValue NixValue
  | NixFile Turtle.FilePath
  | NixNull
  deriving (Generic, Show)

-- * Nixops
--
type DeplArgs = Map.Map NixParam NixValue

-- | Before adding a field here, consider, whether the value in question
--   ought to be passed to Nix.
--   If so, the way to do it is to add a deployment argument (see DeplArgs),
--   which are smuggled across Nix border via --arg/--argstr.
data NixopsConfig = NixopsConfig
  { cName             :: NixopsDepl
  , cGenCmdline       :: Text
  , cTopology         :: Turtle.FilePath
  , cEnvironment      :: Environment
  , cTarget           :: Target
  , cUpdateBucket     :: Text
  , cInstallerURLBase :: Maybe Text
  , cElements         :: [Deployment]
  , cFiles            :: [Text]
  , cDeplArgs         :: DeplArgs
  -- this isn't stored in the config file, but is, instead filled in during initialisation
  , topology          :: SimpleTopo
  , nixpkgs           :: Turtle.FilePath
  } deriving (Generic, Show)

newtype SimpleTopo
  =  SimpleTopo { fromSimpleTopo :: (Map.Map NodeName SimpleNode) }
  deriving (Generic, Show)

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

-- * Topology
--
type RunKademlia = Bool

newtype NodeRoutes = NodeRoutes [[NodeName]]
    deriving (Show)

newtype NodeZone = NodeZone Text
    deriving (Show, Ord, Eq, G.Generic, IsString)
