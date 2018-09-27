{-# LANGUAGE DataKinds, DeriveGeneric, DeriveDataTypeable, FlexibleInstances, GADTs, KindSignatures, OverloadedStrings, RecordWildCards, StandaloneDeriving, ViewPatterns #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-orphans -Wno-missing-signatures #-}

module Nix where

import           Prelude                   hiding (FilePath)

import           Control.Monad.Catch              (Exception, throwM, MonadThrow)
import qualified Data.Aeson                    as AE
import           Data.Aeson                       ((.:), (.=), eitherDecodeStrict, Value)
import qualified Data.ByteString.Lazy.Char8    as L8
import qualified Data.ByteString.Char8         as S8
import           Data.Foldable                    (asum)
import qualified Data.Map.Strict               as Map
import           Data.Maybe
import           Data.Text                        (Text, toTitle)
import qualified Data.Text                     as T
import qualified Data.Text.IO                  as T
import qualified Data.Text.Encoding            as T
import           Data.Text.Encoding.Error         (lenientDecode)
import           Data.Typeable                    (Typeable)
import           Data.Yaml                        (FromJSON(..), ToJSON(..))
import           Filesystem.Path                  (FilePath)
import qualified Filesystem.Path.CurrentOS     as FP
import           Turtle                    hiding (env, err, fold, prefix, procs, e, f, o, x)
import qualified Turtle.Bytes                  as B

import Constants
import Types
import Utils


-- * A bit of Nix types
--
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

githubSource :: L8.ByteString -> Maybe (NixSource 'Github)
githubSource = AE.decode
gitSource    :: L8.ByteString -> Maybe (NixSource 'Git)
gitSource    = AE.decode

-- XXX: make independent of Constants
readSource :: (L8.ByteString -> Maybe (NixSource a)) -> Project -> IO (NixSource a)
readSource parser (projectSrcFile -> path) =
  (fromMaybe (errorT $ format ("File doesn't parse as NixSource: "%fp) path) . parser)
  <$> L8.readFile (T.unpack $ format fp path)

instance FromJSON FilePath where parseJSON = AE.withText "filepath" $ \v -> pure $ fromText v
instance ToJSON   FilePath where toJSON    = AE.String . format fp

-- | The set of first-class types present in Nix
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

-- | Evaluate a nix expression, returning its value in nix syntax.
nixEvalExpr :: Text -> IO Value
nixEvalExpr expr = eval >>= parseNixOutput
  where eval = procNix "nix-instantiate" [ "--json", "--read-write-mode" , "--eval" , "--expr", expr ]

-- | Build a nix expression, returning the store path.
nixBuildExpr :: Text -> IO FilePath
nixBuildExpr expr = fp <$> procNix "nix-build" ["--no-out-link", "--expr", expr]
  where fp = FP.fromText . T.decodeUtf8 . S8.takeWhile (/= '\n')

data NixError = NixError { nixErrorStatus :: Int, nixErrorMessage :: Text } deriving (Show, Typeable)
instance Exception NixError

parseNixOutput :: (MonadThrow m, FromJSON a) => S8.ByteString -> m a
parseNixOutput json = case eitherDecodeStrict json of
  Right val -> pure val
  Left e -> throwM $ NixError 0 ("Could not parse nix output: " <> T.pack e)

procNix :: Text -> [Text] -> IO S8.ByteString
procNix cmd args = log >> B.procStrictWithErr cmd args empty >>= handle
  where
    log = T.putStrLn $ T.intercalate " " (cmd:args)
    handle (ExitSuccess, out, _) = pure out
    handle (ExitFailure status, _, err) = throwM $ NixError status (T.decodeUtf8With lenientDecode err)
