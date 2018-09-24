{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE KindSignatures    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE TypeOperators     #-}
{-# OPTIONS -Weverything -Wno-implicit-prelude #-}

module Main (main) where

import           Control.Monad.Operational    (Program,
                                               ProgramViewT ((:>>=), Return),
                                               singleton, view)
import           Control.Monad.Trans.Except   (ExceptT (ExceptT), runExceptT)
import qualified Data.HashMap.Strict          as HM
import           Data.Int                     (Int64)
import qualified Data.Map                     as Map
import           Data.Maybe                   (fromJust, fromMaybe)
import           Data.Monoid                  ((<>))
import           Data.Reflection              (Given, give, given)
import           Data.String                  (fromString)
import           Data.String.Encode           (encodeString)
import           Data.Time                    (UTCTime, diffUTCTime)
import           Data.Vector                  (Vector)
import qualified Data.Vector                  as V
import           Database.InfluxDB            (Database, Field (FieldInt),
                                               Line (Line), LineField, write,
                                               writeParams)
import           Database.InfluxDB.Types      (Key (Key), Measurement)
import qualified GitHub                       as GH
import qualified GitHub.Data.Id               as GH
import           GitHub.Data.Webhooks.Events  (StatusEvent, StatusEventState (StatusFailureState, StatusSuccessState),
                                               evStatusCommitSha, evStatusRepo,
                                               evStatusState)
import           GitHub.Data.Webhooks.Payload (HookSimpleUser (HookSimpleUser),
                                               whRepoName, whRepoOwner,
                                               whUserLogin)
import           Network.HTTP.Client          (Manager, newManager)
import           Network.HTTP.Client.TLS      (tlsManagerSettings)
import           System.Environment           (getProgName, lookupEnv)

import           Control.Monad.IO.Class       (liftIO)
import qualified Data.Aeson                   as AE
import qualified Data.ByteString.Char8        as C8
import           Network.Wai.Handler.Warp     (run)
import           Servant                      ((:>), Context ((:.)))
import qualified Servant                      as S
import qualified Servant.GitHub.Webhook       as S

type GithubMonad a (k :: GH.RW) = Program (GH.Request k) a
type HasGHAuth = Given (Manager, GH.Auth)

data AccumulatorValue = AccumulatorValue {
    avCommit      :: GH.Commit
  , avStatuses    :: Vector GH.Status
  , avFirstStatus :: Maybe UTCTime
  } deriving Show

newtype Accumulator = Accumulator {
    ghStatusMap :: HM.HashMap (GH.Name GH.Commit) AccumulatorValue
  } deriving Show

getAuth :: IO (Maybe GH.Auth)
getAuth = do
    token <- lookupEnv "GITHUB_TOKEN"
    pure (GH.OAuth . fromString <$> token)

runMonad :: HasGHAuth => GithubMonad a k -> ExceptT GH.Error IO a
runMonad m = do
  let
    (manager, auth) = getGHAuth
  case view m of
    Return a   -> return a
    req :>>= k -> do
        b <- ExceptT $ GH.executeRequestWithMgr manager auth req
        runMonad (k b)

withGHAuth :: (Manager, GH.Auth) -> (HasGHAuth => r) -> r
withGHAuth = give

getGHAuth :: HasGHAuth => (Manager, GH.Auth)
getGHAuth = given

githubRequest :: GH.Request 'GH.RA a -> GithubMonad a 'GH.RA
githubRequest = singleton

githubRequestRW :: GH.Request 'GH.RW a -> GithubMonad a 'GH.RW
githubRequestRW = singleton


foldRequestsToStatuses :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> Accumulator -> GH.SimplePullRequest -> IO Accumulator
foldRequestsToStatuses owner repo acc pr = do
  commits <- getCommits owner repo pr
  V.foldM' (foldCommitsToStatuses owner repo) acc commits

foldCommitsToStatuses :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> Accumulator -> GH.Commit -> IO Accumulator
foldCommitsToStatuses owner repo acc commit = do
  statuses <- getStatuses owner repo commit
  let firstCreatedAt = getStatusFirstCreated statuses
      key = GH.commitSha commit
      value = AccumulatorValue commit statuses firstCreatedAt
  pure $ acc { ghStatusMap = HM.insert key value (ghStatusMap acc) }

getStatusFirstCreated :: Vector GH.Status -> Maybe UTCTime
getStatusFirstCreated statuses =
  if V.length statuses == 0 then Nothing else
    Just $ minimum $ map GH.statusCreatedAt $ V.toList statuses

getPullRequests :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> IO (Vector GH.SimplePullRequest)
getPullRequests owner repo = do
  possiblePullRequests <- runExceptT $ runMonad $ do
    let
      settings :: GH.PullRequestMod
      settings = GH.sortByUpdated <> GH.sortDescending
    githubRequest $ GH.pullRequestsForR owner repo settings $ GH.FetchAtLeast 50
  case possiblePullRequests of
    (Right pullRequests) -> pure pullRequests
    _                    -> pure V.empty

getCommits :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> GH.SimplePullRequest -> IO (Vector GH.Commit)
getCommits owner repo pr = do
  let prnum = GH.simplePullRequestNumber pr
  possibleCommits <- runExceptT $ runMonad $ githubRequest $ GH.pullRequestCommitsR owner repo (GH.Id prnum) GH.FetchAll
  case possibleCommits of
    (Right commits) -> pure commits
    _               -> pure V.empty

getCommit :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> GH.Name GH.Commit -> IO (Either GH.Error GH.Commit)
getCommit owner repo commitSha =
  runExceptT $ runMonad $ githubRequest $ GH.commitR owner repo commitSha

checkStatusCompleted :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> GH.Commit -> IO Bool
checkStatusCompleted owner repo commit = do
  possibleStatusCheck <- runExceptT $ runMonad $ githubRequestRW $ GH.statusForR owner repo (GH.commitSha commit)
  pure $ case possibleStatusCheck of
    (Right (GH.CombinedStatus GH.StatusFailure _ _ _ _ _ _)) -> True
    (Right (GH.CombinedStatus GH.StatusSuccess _ _ _ _ _ _)) -> True
    _                                                        -> False

getStatuses :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> GH.Commit -> IO (Vector GH.Status)
getStatuses owner repo commit = do
  statusCompleted <- checkStatusCompleted owner repo commit
  possibleStatuses <- runExceptT $ runMonad $ githubRequestRW $ GH.statusesForR owner repo (GH.commitSha commit) GH.FetchAll
  if not statusCompleted then pure V.empty else
    case possibleStatuses of
      (Right statuses) -> pure statuses
      _                -> pure V.empty

processStatuses :: (GH.Name GH.Commit, AccumulatorValue) -> IO ()
processStatuses (nameCommit, AccumulatorValue _commit statuses firstCreatedAt) = do
  let
      database :: Database
      database = "ci_statistics"
      measurement :: Measurement
      measurement = "ci_statistics"
      time = firstCreatedAt
      tags :: [ ( Key, Key ) ]
      tags = [
          ("commit", Key $ GH.untagName nameCommit)
        --, ("pr", Key $ tshow prnum)
        ]
      fields :: [ ( Key, LineField ) ]
      fields = V.toList $ V.map (statusToField time) statuses
      entry = Line measurement
             (Map.fromList tags)
             (Map.fromList fields)
             time
  if V.length statuses > 0 then
    write (writeParams database) entry
  else
    pure ()

statusToField :: Maybe UTCTime -> GH.Status -> (Key, LineField)
statusToField createdAt status = statusField
  where
    statusField :: ( Key, LineField )
    statusField = ( Key context, FieldInt timeInSeconds )
    context = fromJust $ GH.statusContext status
    timeInSeconds :: Int64
    timeInSeconds = round $ diffUTCTime statusUpdatedAt justCreatedAt
    statusUpdatedAt = GH.statusUpdatedAt status
    justCreatedAt = fromJust createdAt

manualInfluxImport :: IO ()
manualInfluxImport = do
  manager <- newManager tlsManagerSettings
  auth' <- getAuth
  let
      owner :: GH.Name GH.Owner
      owner = "input-output-hk"
      repo :: GH.Name GH.Repo
      repo = "cardano-sl"
  case auth' of
    Nothing -> return ()
    Just auth -> withGHAuth (manager, auth) $ do
      pullRequests <- getPullRequests owner repo
      acc <- V.foldM' (foldRequestsToStatuses owner repo) (Accumulator HM.empty) (V.take 2 pullRequests)
      mapM_ processStatuses $ HM.toList $ ghStatusMap acc

influxImportCommit :: HasGHAuth => GH.Name GH.Owner -> GH.Name GH.Repo -> GH.Name GH.Commit -> IO ()
influxImportCommit owner repo commitSha = do
    possibleCommit <- getCommit owner repo commitSha
    case possibleCommit of
      Left _       -> putStrLn "An error occurred loading the commit"
      Right commit -> do
        acc <- foldCommitsToStatuses owner repo (Accumulator HM.empty) commit
        putStrLn "Importing commit"
        mapM_ processStatuses $ HM.toList $ ghStatusMap acc

main :: IO ()
main = do
  self <- getProgName
  let
      go :: String -> IO ()
      go "github-webhook-util" = servantMain
      go "import-prs"          = manualInfluxImport
      go _                     = servantMain
  putStrLn $ "running " ++ self
  go self


servantMain :: IO ()
servantMain = do
  putStrLn "starting servant on port 8081"
  possibleKey <- lookupEnv "GITHUB_SERVANT_SECRET"
  manager <- newManager tlsManagerSettings
  auth' <- getAuth
  let
      keyString = fromMaybe "" possibleKey
      key :: C8.ByteString
      key = encodeString keyString
  case auth' of
    Nothing ->
      putStrLn "An error occurred with GH auth. Did you export the env var???"
    Just auth -> withGHAuth (manager, auth) $
      run 8082 (app (S.gitHubKey $ pure key))

app :: HasGHAuth => S.GitHubKey AE.Object -> S.Application
app key
  = S.serveWithContext
    (S.Proxy :: S.Proxy API)
    (key :. S.EmptyContext)
    server

server :: HasGHAuth => S.Server API
server = anyEvent

anyEvent :: HasGHAuth => S.RepoWebhookEvent -> ((), AE.Object) -> S.Handler ()
anyEvent _ (_, value) = liftIO $ do
  let
      gh_event :: StatusEvent
      gh_event = case AE.fromJSON $ AE.Object value of
        AE.Error err  -> error err
        AE.Success op -> op
      commitSha = GH.mkCommitName $ evStatusCommitSha gh_event
      repoObject = evStatusRepo gh_event
      userObject = whRepoOwner repoObject
      repo = GH.mkRepoName $ whRepoName repoObject
      owner = GH.mkOwnerName $ case userObject of
        Left (HookSimpleUser username _ _) -> username
        Right userObject'                  -> whUserLogin userObject'

      statusState = evStatusState gh_event
  case statusState of
    StatusFailureState -> influxImportCommit owner repo commitSha
    StatusSuccessState -> influxImportCommit owner repo commitSha
    _                  -> putStrLn "ignoring, as state is not a success or fail!"

type API
  = "github-webhooks"
    :> S.GitHubEvent '[ 'S.WebhookStatusEvent, 'S.WebhookPingEvent ]
    :> S.GitHubSignedReqBody '[S.JSON] AE.Object
    :> S.Post '[S.JSON] ()
