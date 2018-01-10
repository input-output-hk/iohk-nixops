{-# OPTIONS_GHC -Weverything -Wno-unsafe -Wno-implicit-prelude #-}
{-# LANGUAGE DeriveGeneric #-}

module Cardano where

import           Data.Aeson          (FromJSON)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Text           as T
import           GHC.Generics        (Generic)

type ConfigurationYaml = HashMap.HashMap T.Text ConfigurationRoot

data ConfigurationRoot = ConfigurationRoot {
    update :: ConfigurationUpdate
  } deriving (Show, Generic, Eq)

data ConfigurationUpdate = ConfigurationUpdate {
    applicationVersion :: Integer
  } deriving (Show, Generic, Eq)

instance FromJSON ConfigurationRoot
instance FromJSON ConfigurationUpdate
