{-# LANGUAGE DataKinds, DeriveGeneric, FlexibleInstances, GADTs, KindSignatures, OverloadedStrings, RecordWildCards, StandaloneDeriving, ViewPatterns #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-orphans -Wno-missing-signatures #-}

module Nix where

import qualified Data.Aeson                    as AE
import           Data.Aeson                       ((.:), (.=))
import qualified Data.ByteString.Lazy          as BL
import           Data.ByteString.Lazy.Char8       (ByteString)
import           Data.Foldable                    (asum)
import qualified Data.Map.Strict               as Map
import           Data.Maybe
import           Data.Text
import qualified Data.Text                     as T
import           Data.Yaml                        (FromJSON(..), ToJSON(..))
import           GHC.Generics              hiding (from, to)
import           Prelude                   hiding (FilePath)
import           Turtle                    hiding (env, err, fold, inproc, prefix, procs, e, f, o, x)

import Constants
import Types
import Utils


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
    } -> NixSource 'Git
  GithubSource ::
    { ghOwner           :: Text
    , ghRepo            :: Text
    , ghRev             :: Commit
    , ghSha256          :: NixHash
    } -> NixSource 'Github
deriving instance Show (NixSource a)
instance ToJSON (NixSource 'Git) where
  toJSON GitSource{..} = AE.object
   [ "url"             .= fromURL gUrl
   , "rev"             .= fromCommit gRev
   , "sha256"          .= fromNixHash gSha256
   , "fetchSubmodules" .= lowerShowT gFetchSubmodules ]
instance FromJSON (NixSource 'Git) where
  parseJSON = AE.withObject "GitSource" $ \v -> GitSource
      <$> v .: "url"
      <*> v .: "rev"
      <*> v .: "sha256"
      <*> asum [ (v .: "fetchSubmodules")
               , readT . toTitle <$> (v .: "fetchSubmodules")]
instance FromJSON (NixSource 'Github) where
  parseJSON = AE.withObject "GithubSource" $ \v -> GithubSource
      <$> v .: "owner"
      <*> v .: "repo"
      <*> v .: "rev"
      <*> v .: "sha256"

githubSource :: ByteString -> Maybe (NixSource 'Github)
githubSource = AE.decode
gitSource    :: ByteString -> Maybe (NixSource 'Git)
gitSource    = AE.decode

-- XXX: make independent of Constants
readSource :: (ByteString -> Maybe (NixSource a)) -> Project -> IO (NixSource a)
readSource parser (projectSrcFile -> path) =
  (fromMaybe (errorT $ format ("File doesn't parse as NixSource: "%fp) path) . parser)
  <$> BL.readFile (T.unpack $ format fp path)

instance FromJSON FilePath where parseJSON = AE.withText "filepath" $ \v -> pure $ fromText v
instance ToJSON   FilePath where toJSON    = AE.String . format fp

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

fromNixStr :: NixValue -> Text
fromNixStr (NixStr s) = s
fromNixStr x = error $ "fromNixStr, got a non-NixStr: " <> show x
