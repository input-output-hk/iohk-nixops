{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Main where

import Test.Hspec (hspec)
import Spec (spec)
import Universum

main :: IO ()
main = do
  hspec spec
