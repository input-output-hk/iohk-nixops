{-# LANGUAGE OverloadedStrings #-}

module UpdateLogicSpec (spec, main) where

import Test.Hspec
import UpdateLogic
import qualified Data.ByteString.Lazy as LBS

main :: IO ()
main = hspec spec

sampleInput :: LBS.ByteString
sampleInput = "junk\nbuild id is 13711'\r\r\njunk"

spec :: Spec
spec = do
  describe "travis log output" $ do
    it "tests travis log output parsing" $ do
      extractBuildId sampleInput `shouldBe` 13711
