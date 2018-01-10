{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults #-}
{-# LANGUAGE ExplicitForAll    #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}

module Utils where

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
import           Turtle.Prelude            (proc)
import qualified Data.Aeson                    as AE
import qualified Data.Aeson.Types              as AE
import qualified Data.Char                     as C
import           Data.Text                        (Text)
import           GHC.Generics              hiding (from, to)
import           Turtle

fetchCachedUrl :: HasCallStack => T.Text -> T.Text -> T.Text-> IO ()
fetchCachedUrl url name outPath = do
  exitStatus <- proc "nix-build" [ "-E", "with import <nixpkgs> {}; let file = builtins.fetchurl \"" <> url <> "\"; in runCommand \"" <> name <> "\" {} \"ln -sv ${file} $out\"", "-o", outPath ] mempty
  case exitStatus of
    ExitSuccess   -> return ()
    ExitFailure _ -> error "error downloading file"

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

errorT :: Text -> a
errorT = error . T.unpack

-- Currently unused, but that's mere episode of the used/unused/used/unused event train.
-- Let's keep it, because it's too painful to reinvent every time we need it.
jsonLowerStrip :: (Generic a, AE.GToJSON AE.Zero (Rep a)) => Int -> a -> AE.Value
jsonLowerStrip n = AE.genericToJSON $ AE.defaultOptions { AE.fieldLabelModifier = map C.toLower . drop n }
