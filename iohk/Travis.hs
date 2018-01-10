{-# OPTIONS_GHC -Weverything -Wno-unsafe -Wno-implicit-prelude #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Travis where

import           Control.Monad        (guard)
import           Data.Aeson           (FromJSON, defaultOptions,
                                       genericParseJSON, (.:))
import qualified Data.Aeson           as AE
import           Data.Aeson.Types     (fieldLabelModifier)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.HashMap.Strict  as HashMap
import           Data.Maybe           (listToMaybe, mapMaybe)
import           Data.Monoid          ((<>))
import qualified Data.Text            as T
import qualified Data.Yaml            as Y
import           GHC.Generics         (Generic)
import           Utils                (fetchJson)

type BuildId = T.Text
type JobId = Integer
type BuildNumber = Integer
type RepoId = T.Text

data TravisBuild = TravisBuild {
    number   :: T.Text
    , matrix :: [ TravisJobInfo ]
    } deriving (Show, Generic)

data TravisJobInfo = TravisJobInfo {
    tjiId :: JobId
    } deriving (Show, Generic)

data TravisInfo2 = TravisInfo2 {
    ti2state    :: String
    , ti2commit :: T.Text
    } deriving (Show, Generic)

data TravisYaml
  = TravisYaml
  {
    env    :: TravisYamlEnv
  }
  deriving (Show, Generic, Eq)

data TravisYamlEnv
  = TravisYamlEnv
  {
    global :: [ TravisEnvEntry ]
  }
  deriving (Show, Generic, Eq)

data TravisEnvEntry
  = TravisEnvPlain T.Text T.Text
  | TravisEnvSecure Y.Value
  deriving (Show, Generic, Eq)

instance FromJSON TravisBuild
instance FromJSON TravisJobInfo where
    parseJSON = AE.withObject "TravisJobInfo" $ \v -> TravisJobInfo
        <$> v .: "id"
instance FromJSON TravisInfo2 where
    parseJSON = genericParseJSON defaultOptions { fieldLabelModifier = drop 3 }
instance FromJSON TravisYaml
instance FromJSON TravisYamlEnv
instance FromJSON TravisEnvEntry where
    parseJSON value = case value of
      Y.String txt -> do
        let
          (key, value') = T.breakOn "=" txt
        pure $ TravisEnvPlain key (T.drop 1 value')
      Y.Object obj -> case HashMap.lookup "secure" obj of
        Nothing -> fail "no secure in env"
        Just x  -> pure $ TravisEnvSecure x
      _ -> error "unexpected type in .travis.yml env"

lookup' :: T.Text -> [TravisEnvEntry] -> Maybe T.Text
lookup' key = do
  let
    f3 :: T.Text -> TravisEnvEntry -> Maybe T.Text
    f3 needle (TravisEnvPlain key' value') = guard (needle == key') *> Just value'
    f3 _ _                                 = Nothing
  listToMaybe . mapMaybe (f3 key)

fetchTravis2 :: RepoId -> BuildNumber -> IO TravisInfo2
fetchTravis2 repo buildNumber = do
  results <- fetchJson $ "https://api.travis-ci.org/builds?number=" <> (T.pack . show $ buildNumber) <> "&slug=" <> repo
  return $ head results

fetchTravis :: BuildId -> IO TravisBuild
fetchTravis buildId = fetchJson $ "https://api.travis-ci.org/repos/input-output-hk/daedalus/builds/" <> buildId

parseTravisYaml :: LBS.ByteString -> Either String TravisYaml
parseTravisYaml = Y.decodeEither . LBS.toStrict
