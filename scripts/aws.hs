#!/usr/bin/env nix-shell
#! nix-shell -j 4 -i runhaskell -p 'pkgs.haskellPackages.ghcWithPackages (hp: with hp; [ turtle ])' -p awscli
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/f2c4af4e3bd9ecd4b1cf494270eae5fd3ca9e68c.tar.gz

{-# LANGUAGE OverloadedStrings, UnicodeSyntax #-}

import Control.Monad (forM_)
import Data.Maybe
import Data.Monoid ((<>))
import Filesystem.Path.CurrentOS (encodeString)
import Prelude hiding (FilePath)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Turtle


-- * URLs
data URL =
  URL
  { proto ∷ T.Text
  , host  ∷ T.Text
  , key   ∷ T.Text
  } deriving (Show)

ppURL∷ URL → T.Text
ppURL (URL pro ho ke) = pro <> "://" <> ho <> "/" <> ke


-- * Buckets
data Bucket     = Bucket { fromBucket ∷ T.Text } deriving (Show)

defaultBucket = Bucket "daedalus-travis"


-- * Build/release logic
--
data RSpecOSX     = OSX   BuildId       deriving (Show)
data RSpecWin64   = Win64 AppveyorPath  deriving (Show)

data AppveyorPath = AppveyorPath T.Text deriving (Show)
data BuildId      = BuildId      T.Text deriving (Show)

buildURL ∷ BuildId → URL
buildURL (BuildId id) =
  URL "https" "s3.eu-central-1.amazonaws.com" $
  mconcat ["daedalus-travis/Daedalus-installer-", id, ".pkg"]
avpathURL ∷ AppveyorPath → URL
avpathURL (AppveyorPath avp) =
  URL "https" "ci.appveyor.com" $
  mconcat ["api/buildjobs/", avp, "-installer.exe"]


-- * Parametrisation & Main
data Command =
  S3 S3Command Bucket
  deriving (Show)

data S3Command
  = CheckDaedalusReleaseURLs
  | SetDaedalusReleaseBuild RSpecOSX RSpecWin64
  deriving (Show)

parser ∷ Parser Command
parser =
  subcommand "s3" "Control the S3-related AWS-ities."
  (S3 <$> (subcommand "set-daedalus-release-build" "Set the S3 daedalus-<OS>-latest.<EXT> redirect to a particular version."
            (SetDaedalusReleaseBuild
             <$> (OSX   <$> (BuildId      <$> argText "build-id"      "Travis build id.  Example: '0.3.1526'"))
             <*> (Win64 <$> (AppveyorPath <$> argText "appveyor-path" "AppVeyor build subpath.  Example: 'iw5m0firsneia7k2/artifacts/installers/daedalus-win64-0.3.1451.0'")))
           <|>
           subcommand "check-daedalus-release-urls" "Check the Daedalus release URLs." (pure CheckDaedalusReleaseURLs))
      <*> (fromMaybe defaultBucket
           <$> optional (Bucket <$> (argText "bucket" "The S3 bucket to operate on.  Defaults to 'daedalus-travis'."))))

main ∷ IO ()
main = do
  top ← options "Helper CLI around IOHK AWS functionality" parser
  case top of
    S3 cmd bucket → runS3 cmd bucket



osxLive, w64Live ∷ Bucket → URL
osxLive (Bucket b) = URL "http" (b <> ".s3-website.eu-central-1.amazonaws.com") "daedalus-osx-latest.pkg"
w64Live (Bucket b) = URL "http" (b <> ".s3-website.eu-central-1.amazonaws.com") "daedalus-win64-latest.exe"

checkURL ∷ Text → URL → IO ()
checkURL desc url = do
  echo ""
  printf ("============== Checking if "%s%" URL is live:") desc
  echo ""
  shells ("wget --tries=1 --spider " <> ppURL url) empty

-- Note Appveyor URL checking broken
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--
-- Sadly, neither 'curl' nor 'wget --spider' seem to be able to test AppVeyor URLs
-- for liveness.  Which sounds sort of amazing, indeed.
---
runS3 ∷ S3Command → Bucket → IO ()
runS3 CheckDaedalusReleaseURLs bucket = do
  checkURL "OSX release" (osxLive bucket)
  -- checkURL "W64 release" w64Live -- See Note Appveyor URL checking broken

  echo "URLs live:"
  echo ""
  printf ("  OS X:   "%s%"\n") (ppURL $ osxLive bucket)
  printf ("  Win64:  "%s%"\n") (ppURL $ w64Live bucket)

runS3 (SetDaedalusReleaseBuild rsOSX@(OSX id) rsWin64@(Win64 avPath)) bucket = do
  let (osxurl@(URL osxpr osxcn osxpath), w64url@(URL w64pr w64cn w64path)) =
        (buildURL id, avpathURL avPath)

  echo $ unsafeTextToLine $ mconcat [ "Setting Daedalus release redirects to: "]
  echo $ unsafeTextToLine $ mconcat [ "  OS X:   ", ppURL osxurl]
  echo $ unsafeTextToLine $ mconcat [ "  Win64:  ", ppURL w64url]
  checkURL "OSX build" osxurl
  -- checkURL "W64 build" w64url -- See Note Appveyor URL checking broken

  echo "Both URLs live, proceeding to update latest release build references to:"
  echo $ unsafeTextToLine $ mconcat [ "  OS X:  ", ppURL osxurl]
  echo $ unsafeTextToLine $ mconcat [ "  Win64: ", ppURL w64url]
  echo ""

  with (mktempfile "/tmp" "awstmp.json") $ \tmpfile → do
    writeTextFile tmpfile . T.unlines $
      [ "{",
        "    \"IndexDocument\": {",
        "        \"Suffix\":                   \"index.html\"",
        "    },",
        "    \"RoutingRules\": [",
        "        {",
        "            \"Condition\": {",
        "                \"KeyPrefixEquals\":  \"daedalus-osx-latest.pkg\"",
        "            },",
        "            \"Redirect\": {",
        "                \"HttpRedirectCode\": \"303\",",
        ["                \"Protocol\":         \"", osxpr, "\","] & mconcat,
        ["                \"HostName\":         \"", osxcn, "\","] & mconcat,
        ["                \"ReplaceKeyWith\":   \"", osxpath, "\""] & mconcat,
        "            }",
        "        },",
        "        {",
        "            \"Condition\": {",
        "                \"KeyPrefixEquals\":  \"daedalus-win64-latest.exe\"",
        "            },",
        "            \"Redirect\": {",
        "                \"HttpRedirectCode\": \"303\",",
        ["                \"Protocol\":         \"", w64pr, "\","] & mconcat,
        ["                \"HostName\":         \"", w64cn, "\","] & mconcat,
        ["                \"ReplaceKeyWith\":   \"", w64path, "\""] & mconcat,
        "            }",
        "        }",
        "    ]",
        "}"]

    -- shells ("cat " <> format fp tmpfile) empty
    shells ("aws s3api put-bucket-website --bucket " <> fromBucket bucket <> " --website-configuration file://" <> format fp tmpfile) empty
    echo "Done.  Following URLs should be live within a minute:"
    echo ""
    printf ("  OS X:   "%s%"\n") (ppURL $ osxLive bucket)
    printf ("  Win64:  "%s%"\n") (ppURL $ w64Live bucket)

  pure ()
