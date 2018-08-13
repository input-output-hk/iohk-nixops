#! /usr/bin/env nix-shell
#! nix-shell -i runhaskell
{-# LANGUAGE OverloadedStrings, LambdaCase, RecordWildCards #-}

import Prelude hiding (FilePath)
import Turtle
import Data.Text (Text)
import qualified Data.Text as T
import qualified Filesystem.Path.CurrentOS as FP
import qualified System.Process as P

main :: IO ()
main = do
  (roleFile, hosts, force) <- options "Set up nix-darwin with a configuration." parser
  sh $ deployHosts force roleFile hosts

data Force = Force { forceActivateSame :: Bool } deriving Show

parser :: Parser (FilePath, [Text], Force)
parser = (,,) <$> role <*> hosts <*> force
  where
    role = optPath "role" 'r' "Role nix file"
    hosts = some (argText "HOSTS..." "Target machines to SSH into")
    force = Force <$> switch "force-activate-same" 'S' "Run activation script, even if it's the same as current system."

deployHosts :: Force -> FilePath -> [Text] -> Shell ()
deployHosts force roleFile hosts = do
  (drv, outPath) <- instantiateNixDarwin roleFile
  mapM_ (deployHost force drv outPath) hosts

deployHost :: Force -> FilePath -> FilePath -> Text -> Shell ExitCode
deployHost Force{..} drv outPath host = do
  printf ("Copying derivation to "%s%"\n") host
  procs "nix-copy-closure" ["--to", host, tt drv] empty
  printf ("Building derivation on "%s%"\n") host
  procs "ssh" [ host, "nix-store", "-j", "1"
              , "-r", tt drv
              , "--add-root", "/nix/var/nix/gcroots/per-user/$USER/current-system" ] empty
  currentSystem <- T.stripEnd . snd <$> procStrict "ssh" [host, "readlink", "/run/current-system"] empty

  if currentSystem /= tt outPath || forceActivateSame
    then do
      printf ("Activating on "%s%"\n") host
      -- using system instead of procs so that ssh can pass tty to sudo
      let
        args = ["-t", host, "sudo", tt (outPath </> "activate")]
        activate = P.proc "ssh" (map T.unpack args)
      system activate empty
    else do
      printf ("Already deployed to "%s%"\n") host
      pure ExitSuccess

-- | Get the derivation of the nix-darwin system, and its output path,
-- but don't build.
instantiateNixDarwin :: FilePath -> Shell (FilePath, FilePath)
instantiateNixDarwin configuration = do
  drv <- inproc "nix-instantiate" [ "--show-trace", "./lib/build.nix", "-A", "system"
                                  , "--arg", "configuration", tt configuration ] empty
  outPath <- inproc "nix-store" ["-q", "--outputs", format l drv] empty & limit 1
  pure (lineToFilePath drv, lineToFilePath outPath)

lineToFilePath :: Line -> FilePath
lineToFilePath = FP.fromText . lineToText

tt :: FilePath -> Text
tt = format fp
