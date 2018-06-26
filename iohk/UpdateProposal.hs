{-# LANGUAGE OverloadedStrings, LambdaCase, RecordWildCards #-}

module UpdateProposal
  ( UpdateProposalCommand(..)
  , parseUpdateProposalCommand
  , updateProposal
  ) where

import Prelude hiding (FilePath)
import Options.Applicative hiding (action)
import Turtle hiding (Parser, switch, option, date, o, e)
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (formatTime, iso8601DateFormat, defaultTimeLocale)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.ByteString.Lazy.Char8   as L8
import Control.Monad (forM_, forM)
import Filesystem.Path.CurrentOS (encodeString)
import Data.Yaml (decodeFileEither, encodeFile)
import Data.Aeson hiding (Options)
import qualified Data.HashMap.Strict as HM
import qualified Control.Foldl as Fold
import Data.Char (isHexDigit)
import Data.Bifunctor (first)
import Data.Maybe (fromMaybe)
import Data.List (find)

import NixOps ( Options, NixopsConfig(..)
              , nixopsConfigurationKey, configurationKeys
              , getCardanoSLConfig )
import Types ( NixopsDepl(..), Environment(..), Arch(..) )
import UpdateLogic ( InstallersResults(..), CIResult(..)
                   , realFindInstallers, githubWikiRecord
                   , runAWS', uploadHashedInstaller, updateVersionJson
                   , uploadSignature )
import InstallerVersions (GlobalResults(..), InstallerNetwork(..), installerNetwork)
import Utils (tt)

----------------------------------------------------------------------------
-- Command-line arguments

data UpdateProposalCommand = UpdateProposalCommand
    { updateProposalDate :: Maybe Text
    , updateProposalStep :: UpdateProposalStep
    } deriving Show

data UpdateProposalStep
  = UpdateProposalInit
    { updateProposalInitialConfig     :: Either Text UpdateProposalConfig1
    }
  | UpdateProposalFindInstallers
  | UpdateProposalSignInstallers
    { updateProposalGPGUserId         :: Text
    }
  | UpdateProposalUploadS3
  | UpdateProposalSetVersionJSON
  | UpdateProposalGenerate
  | UpdateProposalSubmit
    { updateProposalRelayIP           :: Text
    , updateProposalDryRun            :: Bool
    }
  deriving Show

parseUpdateProposalCommand :: Parser UpdateProposalCommand
parseUpdateProposalCommand = subparser $
     ( command "init"
       (info ((UpdateProposalCommand <$> date <*> (UpdateProposalInit <$> initialInfo)) <**> helper)
         (progDesc "Create template config file and working directory.") ) )
  <> ( command "find-installers"
       (info ((UpdateProposalCommand <$> date <*> pure UpdateProposalFindInstallers) <**> helper)
         (progDesc "Download installer files from the Daedalus build.") ) )
  <> ( command "sign-installers"
       (info ((UpdateProposalCommand <$> date <*> (UpdateProposalSignInstallers <$> userId)) <**> helper)
         (progDesc "Sign installer files with GPG.") ) )
  <> ( command "upload-s3"
       (info ((UpdateProposalCommand <$> date <*> pure UpdateProposalUploadS3) <**> helper)
         (progDesc "Upload installer files to the S3 bucket.") ) )
  <> ( command "set-version-json"
       (info ((UpdateProposalCommand <$> date <*> pure UpdateProposalSetVersionJSON) <**> helper)
         (progDesc "Update the version info file in the the S3 bucket.") ) )
  <> ( command "generate"
       (info ((UpdateProposalCommand <$> date <*> pure UpdateProposalGenerate) <**> helper)
         (progDesc "Create a voting transaction") ) )
  <> ( command "submit"
       (info (UpdateProposalCommand <$> date <*> (UpdateProposalSubmit <$> relayIP <*> dryRun))
         (progDesc "Send update proposal transaction to the network") ) )
  where
    date :: Parser (Maybe Text)
    date = fmap (fmap fromString) . optional . argument str $
              metavar "DATE"
              <> help "Date string to identify the update proposal (default: today)"

    initialInfo :: Parser (Either Text UpdateProposalConfig1)
    initialInfo = (Left <$> fromDate) <|> (Right <$> updateProposalConfig)

    updateProposalConfig :: Parser UpdateProposalConfig1
    updateProposalConfig = UpdateProposalConfig1
      <$> ( option (eitherReader (gitRevision . T.pack))
            (long "revision" <> short 'r' <> metavar "SHA1"
              <> help "Daedalus revision to fetch") )
      <*> ( fmap T.pack $ strOption (long "block-version" <> short 'B' <> metavar "VERSION"
           <> help "Last known block version. Check the wiki for more info.") )
      <*> ( option auto (long "voter-index" <> short 'V' <> metavar "INTEGER"
           <> help "A number representing you, the vote proposer. Check the wiki for more info.") )

    fromDate :: Parser Text
    fromDate = fmap T.pack $ strOption $
               long "from" <> short 'f' <> metavar "DATE"
               <> help "Copy the previous config from date"

    userId :: Parser Text
    userId = fmap T.pack $ strOption $
             long "local-user" <> short 'u' <> metavar "USER-ID"
             <> help "use USER-ID to sign"

    relayIP :: Parser Text
    relayIP = fmap T.pack $ strOption $
              long "relay-ip" <> short 'r' <> metavar "ADDR"
              <> help "IP address of privileged relay"

    dryRun :: Parser Bool
    dryRun = switch ( long "dry-run" <> short 'n' <> help "Don't actually do anything" )

updateProposal :: Options -> NixopsConfig -> UpdateProposalCommand -> IO ()
updateProposal o cfg UpdateProposalCommand{..} = do
  configKey <- maybe (fail "configurationKey not found") pure (nixopsConfigurationKey cfg)
  top <- pwd
  uid <- makeUpdateId (cName cfg) updateProposalDate
  cslPath <- getCardanoSLConfig o
  let opts = commandOptions (workPath top uid) cslPath configKey (cUpdateBucket cfg)
  sh $ case updateProposalStep of
    UpdateProposalInit initial -> updateProposalInit top uid (first (UpdateID (cName cfg)) initial)
    UpdateProposalFindInstallers -> updateProposalFindInstallers opts (cEnvironment cfg)
    UpdateProposalSignInstallers userId -> updateProposalSignInstallers opts userId
    UpdateProposalUploadS3 -> updateProposalUploadS3 opts
    UpdateProposalSetVersionJSON -> updateProposalSetVersionJSON opts
    UpdateProposalGenerate -> updateProposalGenerate opts
    UpdateProposalSubmit relay dryRun ->
      let opts' = opts { cmdRelayIP = Just relay, cmdDryRun = dryRun }
      in updateProposalSubmit opts'

----------------------------------------------------------------------------
-- Parameters files. These are loaded/saved to yaml in the work dir.
-- There are five versions, for each step in the update proposal.

data UpdateProposalConfig1 = UpdateProposalConfig1
  { cfgDaedalusRevision      :: GitRevision
  , cfgLastKnownBlockVersion :: Text
  , cfgVoterIndex            :: Int
  } deriving (Show)

data UpdateProposalConfig2 = UpdateProposalConfig2
  { cfgUpdateProposal1    :: UpdateProposalConfig1
  , cfgInstallersResults  :: InstallersResults
  } deriving (Show)

data UpdateProposalConfig3 = UpdateProposalConfig3
  { cfgUpdateProposal2    :: UpdateProposalConfig2
  , cfgInstallerHashes    :: InstallerHashes
  } deriving (Show)

data InstallerHashes = InstallerHashes
  { cfgInstallerDarwin  :: Text
  , cfgInstallerWindows :: Text
  } deriving (Show)

data UpdateProposalConfig4 = UpdateProposalConfig4
  { cfgUpdateProposal3 :: UpdateProposalConfig3
  , cfgUpdateProposalAddrs :: Text
  } deriving (Show)

data UpdateProposalConfig5 = UpdateProposalConfig5
  { cfgUpdateProposal4 :: UpdateProposalConfig4
  , cfgUpdateProposalId :: Text
  } deriving (Show)

instance FromJSON UpdateProposalConfig1 where
  parseJSON = withObject "UpdateProposalConfig1" $ \o ->
    UpdateProposalConfig1 <$> o .: "daedalusRevision"
                          <*> o .: "lastKnownBlockVersion"
                          <*> o .: "voterIndex"

instance FromJSON GitRevision where
  parseJSON = withText "SHA1" parseGitRevision

instance FromJSON UpdateProposalConfig2 where
  parseJSON = withObject "UpdateProposalConfig2" $ \o ->
    UpdateProposalConfig2 <$> parseJSON (Object o) <*> o .: "installersResults"

instance FromJSON UpdateProposalConfig3 where
  parseJSON = withObject "UpdateProposalConfig3" $ \o ->
    UpdateProposalConfig3 <$> parseJSON (Object o) <*> o .: "installerHashes"

instance FromJSON UpdateProposalConfig4 where
  parseJSON = withObject "UpdateProposalConfig4" $ \o ->
    UpdateProposalConfig4 <$> parseJSON (Object o) <*> o .:? "addrs" .!= ""

instance FromJSON UpdateProposalConfig5 where
  parseJSON = withObject "UpdateProposalConfig5" $ \o ->
    UpdateProposalConfig5 <$> parseJSON (Object o) <*> o .: "proposalId"

instance FromJSON InstallerHashes where
  parseJSON = withObject "InstallerHashes" $ \o ->
    InstallerHashes <$> o .: "darwin" <*> o .: "windows"

instance ToJSON UpdateProposalConfig1 where
  toJSON (UpdateProposalConfig1 r v p) = object [ "daedalusRevision" .= r
                                                , "lastKnownBlockVersion" .= v
                                                , "voterIndex" .= p ]

instance ToJSON GitRevision where
  toJSON (GitRevision r) = String r

instance ToJSON UpdateProposalConfig2 where
  toJSON (UpdateProposalConfig2 p r)
    = mergeObjects (toJSON p) (object [ "installersResults" .= r ])

instance ToJSON UpdateProposalConfig3 where
  toJSON (UpdateProposalConfig3 p h)
    = mergeObjects (toJSON p) (object [ "installerHashes" .= h ])

instance ToJSON UpdateProposalConfig4 where
  toJSON (UpdateProposalConfig4 p a)
    = mergeObjects (toJSON p) (object [ "addrs" .= a ])

instance ToJSON UpdateProposalConfig5 where
  toJSON (UpdateProposalConfig5 p a)
    = mergeObjects (toJSON p) (object [ "updateProposal" .= a ])

instance ToJSON InstallerHashes where
  toJSON (InstallerHashes dh wh) = object [ "darwin" .= dh, "windows" .= wh ]

-- | Adds two json objects together.
mergeObjects :: Value -> Value -> Value
mergeObjects (Object a) (Object b) = Object (a <> b)
mergeObjects _ b = b

----------------------------------------------------------------------------
-- Loading and saving the params file

loadParams :: (Checkable cfg, FromJSON cfg) => CommandOptions -> Shell cfg
loadParams opts = do
  let yaml = encodeString (paramsFile (cmdWorkPath opts))
  printf ("Loading update proposal parameters from "%w%"\n") yaml
  liftIO (decodeFileEither yaml) >>= \case
    Right cfg -> doCheckConfig cfg >> pure cfg
    Left e ->
      let msg = "Could not parse: "%w%"\n" %
                "The update-proposal steps need to be run in order.\n"
      in die $ format msg e

storeParams :: ToJSON cfg => CommandOptions -> cfg -> Shell ()
storeParams opts params = do
  let yaml = encodeString (paramsFile (cmdWorkPath opts))
  printf ("Saving update proposal parameters to "%w%"\n") yaml
  liftIO (encodeFile yaml params)

----------------------------------------------------------------------------
-- Validation of config

-- | Polymorphic function to validate parameters.
class Checkable cfg where
  checkConfig :: cfg -> Maybe Text

instance Checkable UpdateProposalConfig1 where
  checkConfig UpdateProposalConfig1{..}
    | T.null cfgLastKnownBlockVersion = Just "Last known block version must be set"
    | cfgVoterIndex <= 0 = Just "Voter index must be set"
    | otherwise = Nothing

instance Checkable UpdateProposalConfig2 where
  checkConfig (UpdateProposalConfig2 p r) = checkConfig p <|> check r
    where
      check InstallersResults{..}
        | grApplicationVersion <= 0 = Just "Application version must be set"
        | T.null grCardanoCommit = Just "Missing cardano commit"
        | missingVersion Mac64 ciResults = Just "macOS version is missing"
        | missingVersion Win64 ciResults = Just "Windows version is missing"
        | otherwise = Nothing
        where
          GlobalResults{..} = globalResult
          missingVersion arch = not . any ((== arch) . ciResultArch)

instance Checkable UpdateProposalConfig3 where
  checkConfig (UpdateProposalConfig3 p h) = checkConfig p <|> checkConfig h

instance Checkable UpdateProposalConfig4 where
  checkConfig (UpdateProposalConfig4 p a) = checkConfig p <|> checkAddr a
    where
      checkAddr "" = Just "No addresses stored in config. Has the generate step been run?"
      checkAddr _ = Nothing

instance Checkable InstallerHashes where
  checkConfig (InstallerHashes dh wh)
    | T.null dh || T.null wh = Just "Need to set installer hashes"
    | not (isInstallerHash dh) = Just "Bad hash for darwin installer"
    | not (isInstallerHash wh) = Just "Bad hash for windows installer"
    | otherwise = Nothing

-- | Installer hashes are 64 hex digits.
isInstallerHash :: Text -> Bool
isInstallerHash t = T.length t == 64 && T.all isHexDigit t

-- | Wrapper for sha1 hash.
newtype GitRevision = GitRevision { unGitRevision :: Text } deriving (Show, Eq)

-- | Validates sha1 hash text.
gitRevision :: Text -> Either String GitRevision
gitRevision t | T.length t /= 40 = Left "SHA1 revision is not 40 characters"
              | T.any (not . isHexDigit) t = Left "Revision must be all hex digits"
              | otherwise = Right (GitRevision t)

parseGitRevision :: Monad m => Text -> m GitRevision
parseGitRevision t = case gitRevision t of
                       Right rev -> pure rev
                       Left e    -> fail e

-- | Die if not valid.
doCheckConfig :: (MonadIO io, Checkable cfg) => cfg -> io cfg
doCheckConfig cfg = case checkConfig cfg of
                       Nothing -> pure cfg
                       Just e  -> die e

----------------------------------------------------------------------------
-- Update proposal

-- | Update ID is pair of deployment and date tag.
data UpdateID = UpdateID NixopsDepl Text
  deriving Show

-- | The context for running cardano-sl commands relating to an update
-- proposal.
data CommandOptions = CommandOptions
  { cmdWorkPath          :: FilePath
  , cmdCardanoConfigFile :: FilePath
  , cmdCardanoConfigKey  :: Text
  , cmdCardanoLogConfig  :: FilePath
  , cmdDryRun            :: Bool
  , cmdUpdateBucket      :: Text
  , cmdRelayIP           :: Maybe Text
  , cmdRelayPort         :: Int
  } deriving Show

-- | Constructs an UpdateID, using current date as tag if not provided.
makeUpdateId :: NixopsDepl -> Maybe Text -> IO UpdateID
makeUpdateId name mdate = UpdateID name <$> maybe today pure mdate
  where
    today = fromString . fmt <$> getCurrentTime
    fmt = formatTime defaultTimeLocale (iso8601DateFormat Nothing)

-- | Constructs a CommandOptions record.
commandOptions :: FilePath -> FilePath -> Text -> Text -> CommandOptions
commandOptions cmdWorkPath cardanoSource cmdCardanoConfigKey cmdUpdateBucket
  = CommandOptions{..}
  where
    cmdCardanoConfigFile = cardanoSource </> "lib/configuration.yaml"
    cmdCardanoLogConfig = cardanoSource </> "log-configs/cluster.yaml"
    cmdDryRun = False
    cmdRelayIP = Nothing -- not required on all commands
    cmdRelayPort = 3000 -- hard-coded for now

----------------------------------------------------------------------------
-- Paths in the work directory

fmtUpdatePath :: UpdateID -> FilePath
fmtUpdatePath (UpdateID (NixopsDepl name) date) = fromText (name <> "-" <> date)

workPath :: FilePath -> UpdateID -> FilePath
workPath topDir uid = topDir </> "update-proposals" </> fmtUpdatePath uid

paramsFile :: FilePath -> FilePath
paramsFile = (</> "params.yaml")

wikiFile :: FilePath -> FilePath
wikiFile = (</> "wiki.md")

findKeys :: FilePath -> Shell FilePath
findKeys = Turtle.find (ends ".sk")

-- | List all the keys in the update proposal working directory.
findWorkDirKeys :: CommandOptions -> Shell FilePath
findWorkDirKeys opts = findKeys (cmdWorkPath opts </> "keys")

-- | Path to an installer (hash) in the work directory.
installersPath :: CommandOptions -> FilePath -> FilePath
installersPath opts hash = installersDir opts </> hash

-- | Where the installers are downloaded to
installersDir :: CommandOptions -> FilePath
installersDir opts = cmdWorkPath opts </> "installers"

-- | Path to the version info json in the work directory.
versionFile :: CommandOptions -> FilePath
versionFile opts = cmdWorkPath opts </> "daedalus-latest-version.json"

----------------------------------------------------------------------------

-- | Step 1. Init a new work directory
updateProposalInit :: FilePath -> UpdateID -> Either UpdateID UpdateProposalConfig1 -> Shell ()
updateProposalInit top uid initial = do
  let dir = workPath top uid
      yaml = paramsFile dir
      keysDir = top </> "keys"
  printf ("*** Setting up working area for "%fp%"\n") dir
  mktree dir
  testfile yaml >>= \case
    True -> die "Config file already exists, stopping."
    False -> pure ()
  case initial of
    Left fromUid -> do
      let src = paramsFile (workPath top fromUid)
      printf ("Copying from "%fp%"\n") src
      cp src yaml
    Right cfg -> do
      printf "Creating blank template\n"
      liftIO $ encodeFile (encodeString yaml) cfg
  liftIO . sh $ copyKeys keysDir (dir </> "keys")
  mktree (dir </> "installers")
  printf ("*** Now check that "%fp%" is correct.\n") yaml

-- | Copy secret keys out of top-level keys directory into the work directory.
copyKeys :: FilePath -> FilePath -> Shell ()
copyKeys src dst = mkdir dst >> findKeys src >>= copy
  where copy key = do
          let dst' = dst </> filename key
          printf ("Copying "%fp%" -> "%fp%"\n") key dst'
          cp key dst'

----------------------------------------------------------------------------

-- | Step 2. Find installers and download them.
updateProposalFindInstallers :: CommandOptions -> Environment -> Shell ()
updateProposalFindInstallers opts env = do
  params <- loadParams opts
  void $ doCheckConfig params
  echo "*** Finding installers"
  let rev = unGitRevision . cfgDaedalusRevision $ params
      destDir = Just (installersDir opts)
  res <- liftIO $ realFindInstallers (configurationKeys env) (installerForEnv env) rev destDir
  echo "*** Finished."
  writeWikiRecord opts res
  storeParams opts (UpdateProposalConfig2 params res)

-- | Checks if an installer from a CI result matches the environment
-- that iohk-ops is running under.
installerForEnv :: Environment -> CIResult -> Bool
installerForEnv env = matchNet . installerNetwork . ciResultLocalPath
  where matchNet n = case env of
          Production  -> n == Just InstallerMainnet
          Staging     -> n == Just InstallerStaging
          Development -> True
          Any         -> False

writeWikiRecord :: CommandOptions -> InstallersResults -> Shell ()
writeWikiRecord opts res = do
  let md = wikiFile (cmdWorkPath opts)
  printf ("*** Writing wiki table entry to "%fp%"\n") md
  liftIO $ TIO.writeFile (encodeString md) $ githubWikiRecord res

----------------------------------------------------------------------------

-- | Step 2a. (Optional) Sign installers with GPG. This will leave
-- .asc files next to the installers which will be picked up in the
-- upload S3 step.
updateProposalSignInstallers :: CommandOptions -> Text -> Shell ()
updateProposalSignInstallers opts@CommandOptions{..} userId = do
  params <- loadParams opts
  void $ doCheckConfig params
  mapM_ signInstaller (map ciResultLocalPath . ciResults . cfgInstallersResults $ params)
  where
    signInstaller f = procs "gpg2" ["-u", userId, "--detach-sig", "--armor", "--sign", tt f] empty

----------------------------------------------------------------------------

-- | Step 3. Hash installers and upload to S3
updateProposalUploadS3 :: CommandOptions -> Shell ()
updateProposalUploadS3 opts@CommandOptions{..} = do
  params@UpdateProposalConfig2{..} <- loadParams opts
  void $ doCheckConfig params
  echo "*** Hashing installers with sha256sum"
  sha256 <- getHashes sha256sum cfgInstallersResults
  echo "*** Hashing installers with cardano-auxx"
  hashes <- getHashes (cardanoHashInstaller opts) cfgInstallersResults
  printf ("*** Uploading installers to S3 bucket "%s%"\n") cmdUpdateBucket
  urls <- uploadInstallers cmdUpdateBucket cfgInstallersResults hashes
  printf ("*** Uploading signatures to same S3 bucket.\n")
  signatures <- uploadSignatures cmdUpdateBucket cfgInstallersResults
  printf ("*** Writing "%fp%"\n") (versionFile opts)
  let dvis = makeDownloadVersionInfo cfgInstallersResults urls hashes sha256 signatures
  liftIO $ writeVersionJSON (versionFile opts) dvis
  storeParams opts (UpdateProposalConfig3 params hashes)

uploadInstallers :: Text -> InstallersResults -> InstallerHashes -> Shell (Text, Text)
uploadInstallers bucket res InstallerHashes{..} = runAWS' $ do
  darwin <- needResult Mac64 res $ upload cfgInstallerDarwin
  windows <- needResult Win64 res $ upload cfgInstallerWindows
  pure (darwin, windows)
  where
    upload hash ci = do
      printf ("***   "%s%"  "%fp%"\n") hash (ciResultLocalPath ci)
      uploadHashedInstaller bucket (ciResultLocalPath ci) (globalResult res) hash

-- | Apply a hashing command to all the installer files.
getHashes :: (FilePath -> Shell Text) -> InstallersResults -> Shell InstallerHashes
getHashes getHash res = do
  cfgInstallerDarwin <- needResult Mac64 res resultHash
  cfgInstallerWindows <- needResult Win64 res resultHash
  pure $ InstallerHashes{..}
  where
   resultHash = getHash . ciResultLocalPath

-- | Run cardano-auxx "hash-installer" command on a file and capture
-- its output.
cardanoHashInstaller :: CommandOptions -> FilePath -> Shell Text
cardanoHashInstaller opts i = runCommands opts [cmd] & grep hash & sed hash & chomp
  where
    cmd = format ("hash-installer "%fp) i
    hash = text "Hash" *> star anyChar *> text " is " *> plus hexDigit

-- | Capture output of sha256sum from gnu coreutils.
sha256sum :: FilePath -> Shell Text
sha256sum f = inproc "sha256sum" ["--binary", tt f] empty & hash & chomp
  where hash = sed (prefix (plus hexDigit))

chomp :: Shell Line -> Shell Text
chomp = fmap T.stripEnd . strict . limit 1

-- | Slurp in previously created signatures.
uploadSignatures :: Text -> InstallersResults -> Shell [(Arch, Maybe Text)]
uploadSignatures bucket InstallersResults{..} = forM ciResults $ \res -> do
  sig <- liftIO $ uploadResultSignature bucket res
  pure (ciResultArch res, sig)

uploadResultSignature :: Text -> CIResult -> IO (Maybe Text)
uploadResultSignature bucket res = liftIO $ maybeReadFile sigFile >>= \case
  Just sig -> do
    runAWS' $ uploadSignature bucket sigFile
    pure $ Just sig
  Nothing -> do
    printf ("***   Signature file "%fp%" does not exist.\n") sigFile
    pure Nothing
  where
    sigFile = ciResultLocalPath res <.> "asc"
    maybeReadFile f = testfile f >>= \case
      True -> Just <$> readTextFile f
      False -> pure Nothing

makeDownloadVersionInfo :: InstallersResults
                        -> (Text, Text)
                        -> InstallerHashes -> InstallerHashes
                        -> [(Arch, Maybe Text)]
                        -> [DownloadVersionInfo]
makeDownloadVersionInfo InstallersResults{..} (macosURL, windowsURL) hashes sha256 sigs = [macos, win64]
  where
    macos = DownloadVersionInfo
      { dviPlatform = "macos"
      , dviVersion = grDaedalusVersion globalResult
      , dviURL = macosURL
      , dviHash = cfgInstallerDarwin hashes
      , dviSHA256 = cfgInstallerDarwin sha256
      , dviSignature = join (lookup Mac64 sigs)
      }
    win64 = DownloadVersionInfo
      { dviPlatform = "win64"
      , dviVersion = grDaedalusVersion globalResult
      , dviURL = windowsURL
      , dviHash = cfgInstallerWindows hashes
      , dviSHA256 = cfgInstallerWindows sha256
      , dviSignature = join (lookup Win64 sigs)
      }

-- | Intermediate data type for the daeadlus download json file.
data DownloadVersionInfo = DownloadVersionInfo
  { dviPlatform  :: Text
  , dviVersion   :: Text
  , dviURL       :: Text
  , dviHash      :: Text
  , dviSHA256    :: Text
  , dviSignature :: Maybe Text
  } deriving (Show)

-- | Splat version info to an aeson object.
downloadVersionInfoObject :: [DownloadVersionInfo] -> Value
downloadVersionInfoObject = foldr mergeObjects (Object mempty) . map toObject
  where
    toObject :: DownloadVersionInfo -> Value
    toObject DownloadVersionInfo{..} = Object (HM.fromList attrs)
      where
        attrs = [ (dviPlatform <> k, String v) | (k, v) <-
                    [ (""         , dviVersion)
                    , ("URL"      , dviURL)
                    , ("Hash"     , dviHash)
                    , ("SHA256"   , dviSHA256)
                    , ("Signature", fromMaybe "" dviSignature)
                    ] ]

writeVersionJSON :: FilePath -> [DownloadVersionInfo] -> IO ()
writeVersionJSON out dvis = L8.writeFile (encodeString out) (encode v)
  where v = downloadVersionInfoObject dvis

----------------------------------------------------------------------------

-- | Step 3a. Update version JSON file in S3.
-- Doesn't do anything except upload the file which was previously
-- written into the work dir.
updateProposalSetVersionJSON :: CommandOptions -> Shell ()
updateProposalSetVersionJSON opts@CommandOptions{..} = do
  params <- loadParams opts :: Shell UpdateProposalConfig3
  void $ doCheckConfig params
  printf ("*** Uploading version JSON from "%fp%"\n") (versionFile opts)
  contents <- liftIO $ L8.readFile (encodeString $ versionFile opts)
  url <- liftIO $ updateVersionJson cmdUpdateBucket contents
  printf ("*** Uploaded to "%s%"\n") url

----------------------------------------------------------------------------

-- | Step 4. Generate database with keys, download installers.
updateProposalGenerate :: CommandOptions -> Shell ()
updateProposalGenerate opts@CommandOptions{..} = do
  params@UpdateProposalConfig3{..} <- loadParams opts
  void $ doCheckConfig cfgInstallerHashes
  echo "*** Copying and checking installers."
  copyInstallerFiles opts (cfgInstallersResults cfgUpdateProposal2) cfgInstallerHashes
  echo "*** Generating keys and database."
  addrs <- doGenerate opts params
  storeParams opts (UpdateProposalConfig4 params addrs)
  echo "*** Finished generate step. Next step is to submit."
  echo "*** Carefully check the parameters yaml file."

needResult :: MonadIO io => Arch -> InstallersResults -> (CIResult -> io a) -> io a
needResult arch rs action = case Data.List.find ((== arch) . ciResultArch) (ciResults rs) of
  Just r -> action r
  Nothing -> die $ format ("The CI result for "%w%" is required but was not found.") arch

-- | Copy installers to a filename which is their hash and then use
-- "file" to verify that installers are of the expected type. Exit the
-- program otherwise.
copyInstallerFiles :: CommandOptions -> InstallersResults -> InstallerHashes -> Shell ()
copyInstallerFiles opts res InstallerHashes{..} = do
  needResult Mac64 res $ copy "xar" cfgInstallerDarwin
  needResult Win64 res $ copy "MS Windows" cfgInstallerWindows

  where
    copy :: Text -> Text -> CIResult -> Shell ()
    copy magic hash res = do
      let dst = installersPath opts (fromText hash)
      cp (ciResultLocalPath res) dst
      checkMagic magic dst

    checkMagic :: Text -> FilePath -> Shell ()
    checkMagic magic dst = do
      info <- file dst
      unless (magic `T.isInfixOf` info) $
        die $ format ("Downloaded installer file "%fp%" is not of type "%s%". Instead is:\n"%s%"\n") dst magic info

    file :: FilePath -> Shell Text
    file dst = snd <$> procStrict "file" [tt dst] empty

doGenerate :: CommandOptions -> UpdateProposalConfig3 -> Shell Text
doGenerate opts UpdateProposalConfig3{..} = do
  keys <- fold (findWorkDirKeys opts) Fold.list
  mapM_ (rearrangeKey opts) keys
  let cmds = map (format ("add-key "%fp%" primary:true")) keys ++ [ "listaddr" ]
  grabAddresses $ runCommands opts cmds

-- | Runs the "cardano-keygen rearrange" command on a single key file.
rearrangeKey :: MonadIO io => CommandOptions -> FilePath -> io ()
rearrangeKey opts sk = liftIO . sh $ runTool opts "cardano-keygen" ["rearrange", "--mask", tt sk]

-- | Filters just the output where it shows available addresses.
grabAddresses :: Shell Line -> Shell Text
grabAddresses = fmap grab . flip fold Fold.list
  where grab = T.unlines . dropWhile (not . T.isPrefixOf "Available addresses") . map (format l)

----------------------------------------------------------------------------

-- | Step 5. Submit update proposal.
updateProposalSubmit :: CommandOptions -> Shell ()
updateProposalSubmit opts@CommandOptions{..} = do
  echo "*** Submitting update proposal"
  params <- loadParams opts
  fmap (format l) <$> doPropose opts params >>= \case
    Just updateId -> do
      storeParams opts (UpdateProposalConfig5 params updateId)
      echo "*** Update proposal submitted!"
    Nothing -> echo "*** Submission of update proposal failed."

doPropose :: CommandOptions -> UpdateProposalConfig4 -> Shell (Maybe Line)
doPropose opts cfg = fold (runCommands opts [cmd] & grep isUpdateId) Fold.last
  where
    cmd = format upd cfgVoterIndex cfgLastKnownBlockVersion appVer
          (inst cfgInstallerWindows) (inst cfgInstallerDarwin)
    upd = "propose-update "%d%" vote-all:true "%s%" ~software~csl-daedalus:"%d%" (upd-bin \"win64\" "%fp%") (upd-bin \"macos64\" "%fp%")"
    isUpdateId = count 64 hexDigit
    UpdateProposalConfig1{..} = cfgUpdateProposal1
    UpdateProposalConfig2{..} = cfgUpdateProposal2
    UpdateProposalConfig3{..} = cfgUpdateProposal3 cfg
    inst f = installersPath opts (fromText . f $ cfgInstallerHashes)
    appVer = grApplicationVersion . globalResult $ cfgInstallersResults

----------------------------------------------------------------------------
-- Running cardano tools

runCommands :: CommandOptions -> [Text] -> Shell Line
runCommands opts@CommandOptions{..} cmds = runTool opts "cardano-auxx" args
  where
    args = auxxOpts ++ peerOpts ++ commandOpts
    auxxOpts   = [ "--log-config", tt cmdCardanoLogConfig
                 , "--logs-prefix", tt (cmdWorkPath </> "logs")
                 , "--db-path", tt (cmdWorkPath </> "db")
                 , "--mode", "with-config"
                 ]
    peerOpts   = case cmdRelayIP of
                   Just addr -> [ "--peer", format (s%":"%d) addr cmdRelayPort ]
                   Nothing -> []
    commandOpts = [ "cmd", "--commands", T.intercalate "; " cmds ]

-- | Run a cardano-sl tool with the common options passed.
-- Will capture the output, as well as printing it.
runTool :: CommandOptions -> Text -> [Text] -> Shell Line
runTool opts cmd args = do
  let args' = commonOpts opts ++ args
  printf (s%" "%s%"\n") cmd (T.intercalate " " args')
  if cmdDryRun opts
    then echo "(dry-run, doing nothing)" >> empty
    else do
      line <- inproc cmd args' empty
      echo line
      pure line

commonOpts :: CommandOptions -> [Text]
commonOpts CommandOptions{..} = [ "--system-start", "0"
                                , "--configuration-file", tt cmdCardanoConfigFile
                                , "--configuration-key", cmdCardanoConfigKey
                                ]

----------------------------------------------------------------------------
-- Testing utils, just for ghci.

-- | Build tools with nix, then adjust prepend them to PATH.
loadTools :: MonadIO io => FilePath -> io ()
loadTools dir = forM_ ["cardano-sl-tools", "cardano-sl-auxx"] $ \t -> do
  p <- single $ inproc "nix-build" [tt (dir </> "default.nix"), "-A", t] empty
  let bin = fromText (format l p) </> "bin"
  prependPath bin

prependPath :: MonadIO io => FilePath -> io ()
prependPath p = need "PATH" >>= \case
  Just path -> export "PATH" (tt p <> ":" <> path)
  Nothing -> pure ()
