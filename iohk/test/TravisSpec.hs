{-# LANGUAGE OverloadedStrings #-}

module TravisSpec (spec, main) where

import Test.Hspec
import Travis
import qualified Data.ByteString.Lazy as LBS

main :: IO ()
main = hspec spec

sampleTravisYml :: LBS.ByteString
sampleTravisYml = "env:\n  global:\n    - VERSION=0.6\n    - CARDANO_SL_BRANCH=cardano-sl-0.6\n    - secure: \"ciphertext\"\n"

spec :: Spec
spec = do
  describe "travis.yml" $ do
    it "tests .travis.yml parsing" $ do
      parseTravisYaml sampleTravisYml `shouldBe` Right (TravisYaml {env = TravisYamlEnv {global = [TravisEnvPlain "VERSION" "0.6",TravisEnvPlain "CARDANO_SL_BRANCH" "cardano-sl-0.6",TravisEnvSecure ("ciphertext")]}})
