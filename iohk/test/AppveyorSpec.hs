{-# LANGUAGE OverloadedStrings #-}

module AppveyorSpec (spec, main) where

import Test.Hspec
import qualified Data.ByteString.Lazy as LBS
import Data.Aeson
import Data.HashMap.Strict
import Appveyor

main :: IO ()
main = hspec spec

sampleTravisYml :: LBS.ByteString
sampleTravisYml = "env:\n  global:\n    - VERSION=0.6\n    - CARDANO_SL_BRANCH=cardano-sl-0.6\n    - secure: \"ciphertext\"\n"

artifactJson :: LBS.ByteString
artifactJson = encode $ Object (fromList [("fileName", "installer.exe"), ("name", "windows installer")])

spec :: Spec
spec = do
  describe "Appveyor" $ do
    it "AppveyorArtifact parse" $ do
      (decode artifactJson :: Maybe AppveyorArtifact) `shouldBe` Just (AppveyorArtifact "installer.exe" "windows installer")

