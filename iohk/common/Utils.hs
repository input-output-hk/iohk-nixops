{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults #-}
{-# LANGUAGE ExplicitForAll    #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Utils where

import           Prelude                   hiding (FilePath)
import           Data.Aeson                (FromJSON, decode)
import qualified Data.ByteString.Lazy      as LBS
import           Data.Monoid               ((<>))
import qualified Data.Text                 as T
import qualified Data.Text.Lazy            as LT
import qualified Data.Text.Lazy.Encoding   as LT
import           GHC.Stack                 (HasCallStack)
import           Network.HTTP.Client       (httpLbs, parseRequest,
                                            requestHeaders, responseBody)
import           Network.HTTP.Client.TLS   (newTlsManager)
import           Network.HTTP.Types.Header (RequestHeaders)
import           System.Exit               (ExitCode (ExitFailure, ExitSuccess))
import qualified Data.Aeson                    as AE
import qualified Data.Char                     as C
import           Data.Text                        (Text)
import           GHC.Generics              hiding (from, to)
import           Turtle
import           Network.AWS               (Region)
import           Network.AWS.S3            (BucketName(..), ObjectKey(..))
import qualified Network.AWS.Data          as AWS

fetchCachedUrl :: HasCallStack => T.Text -> FilePath -> FilePath -> IO ()
fetchCachedUrl url name outPath = fetchCachedUrl' url name outPath Nothing

fetchCachedUrlWithSHA1 :: HasCallStack => T.Text -> T.Text -> FilePath -> FilePath -> IO ()
fetchCachedUrlWithSHA1 sha1 url name outPath = fetchCachedUrl' url name outPath (Just sha1)

fetchCachedUrl' :: HasCallStack => T.Text -> FilePath -> FilePath -> Maybe T.Text -> IO ()
fetchCachedUrl' url name outPath sha1 = proc "nix-build" args mempty >>= handleExit
  where
    args = [ "-E", format ("with import <nixpkgs> {}; let file = "%s%"; in runCommand \""%fp%"\" {} \"ln -sv ${file} $out\"") fetchExpr name, "-o", format fp outPath ]
    fetchExpr = case sha1 of
      Just hash -> format ("pkgs.fetchurl { url = \""%s%"\"; sha1 = \""%s%"\"; }") url hash
      Nothing   -> "builtins.fetchurl \"" <> url <> "\""
    handleExit ExitSuccess     = return ()
    handleExit (ExitFailure _) = error "error downloading file"

fetchJson :: HasCallStack => FromJSON a => T.Text -> IO a
fetchJson = fetchJson' mempty

fetchJson' :: HasCallStack => FromJSON a => RequestHeaders -> T.Text -> IO a
fetchJson' extraHeaders url = do
  reply <- fetchUrl extraHeaders url
  let
    maybeObj :: FromJSON a => Maybe a
    maybeObj = decode reply
  case maybeObj of
    Just v  -> return v
    Nothing -> error $ "unable to parse json: " <> LT.unpack (LT.decodeUtf8 reply) <> " from: " <> T.unpack url

fetchUrl :: RequestHeaders -> T.Text -> IO LBS.ByteString
fetchUrl extraHeaders url = do
  man <- newTlsManager
  reqUrl <- (parseRequest . T.unpack) url
  let req' = reqUrl { requestHeaders = [ ("User-Agent", "https://github.com/input-output-hk/iohk-ops") ] <> extraHeaders }
  resp <- httpLbs req' man
  return $ responseBody resp



-- * Flags & enumerables
--
every :: (Bounded a, Enum a) => [a]
every = enumFromTo minBound maxBound

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

-- * Utils
showT :: Show a => a -> Text
showT = T.pack . show

readT :: Read a => Text -> a
readT = read . T.unpack

lowerShowT :: Show a => a -> Text
lowerShowT = T.toLower . T.pack . show

errorT :: HasCallStack => Text -> a
errorT = error . T.unpack

tt :: FilePath -> Text
tt = format fp

-- Currently unused, but that's mere episode of the used/unused/used/unused event train.
-- Let's keep it, because it's too painful to reinvent every time we need it.
jsonLowerStrip :: (Generic a, AE.GToJSON AE.Zero (Rep a)) => Int -> a -> AE.Value
jsonLowerStrip n = AE.genericToJSON $ AE.defaultOptions { AE.fieldLabelModifier = map C.toLower . drop n }

-- | Returns the public download URL for an object in S3, according to
-- the AWS path-style convention.
-- https://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAPI.html
s3Link :: Region -> BucketName -> ObjectKey -> Text
s3Link region (BucketName bucket) (ObjectKey key) =
  mconcat [ "https://s3-", AWS.toText region, ".amazonaws.com/" , bucket, "/", key ]
