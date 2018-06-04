{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall -Wno-name-shadowing -Wno-missing-signatures -Wno-type-defaults #-}

module Constants where

import           Data.Monoid                      ((<>))
import           GHC.Stack
import           Prelude                   hiding (FilePath)
import           Time.Types
import           Turtle                    hiding (env, err, fold, inproc, prefix, procs, e, f, o, x)

import Types
import Utils


awsPublicIPURL       :: URL
awsPublicIPURL       = "http://169.254.169.254/latest/meta-data/public-ipv4"

defaultEnvironment   = Development
defaultTarget        = AWS
defaultNode          = NodeName "c-a-1"
defaultNodePort      = PortNo 3000

defaultIOPSBranch    = Branch "develop"

defaultHold          = 1200 :: Seconds -- 20 minutes

defaultJournaldTimeSpec = JournaldTimeSpec "6 hours ago"

explorerNode         = NodeName "explorer"

orgs                 :: [NodeOrg]
orgs                 = enumFromTo minBound maxBound
defaultOrg           = IOHK
accessKeyChain       = "IOHKroute53accessKeyId" : [ AccessKeyId $ showT org <> "accessKeyId"
                                                  | org <- orgs ]

simpleTopoFile       :: FilePath
simpleTopoFile       = "topology.nix"


-- * Project-related constants
--
data Project
  = CardanoSL
  | IOHKOps
  | Nixpkgs
  | Stack2nix
  | Nixops
  deriving (Bounded, Enum, Eq, Read, Show)

projectURL     :: Project -> URL
projectURL     CardanoSL       = "https://github.com/input-output-hk/cardano-sl"
projectURL     IOHKOps         = "https://github.com/input-output-hk/iohk-nixops"
projectURL     Nixpkgs         = "https://github.com/nixos/nixpkgs"
projectURL     Stack2nix       = "https://github.com/input-output-hk/stack2nix"
projectURL     Nixops          = "https://github.com/input-output-hk/nixops"

projectSrcFile :: Project -> FilePath
projectSrcFile CardanoSL       = "cardano-sl-src.json"
projectSrcFile Nixpkgs         = "nixpkgs-src.json"
projectSrcFile Stack2nix       = "stack2nix-src.json"
projectSrcFile IOHKOps         = error "Feeling self-referential?"
projectSrcFile Nixops          = error "No corresponding -src.json spec for 'nixops' yet."


-- * Environment-specificity
--
data EnvSettings =
  EnvSettings
  { envDeployerUser      :: Username
  , envDefaultConfigurationKey :: ConfigurationKey
  , envDefaultConfig     :: FilePath
  , envDefaultTopology   :: FilePath
  , envDeploymentFiles   :: [FileSpec]
  }

type FileSpec = (Deployment, Target, Text)

envSettings :: HasCallStack => Environment -> EnvSettings
envSettings env =
  let deplAgnosticFiles      = [ (Every,          All, "deployments/keypairs.nix")
                               , (Explorer,       All, "deployments/cardano-explorer.nix")
                               , (ReportServer,   All, "deployments/report-server.nix")
                               , (Faucet,         All, "deployments/cardano-faucet.nix")
                               , (Nodes,          All, "deployments/cardano-nodes.nix")
                               , (Infra,          All, "deployments/infrastructure.nix")
                               , (Infra,          AWS, "deployments/infrastructure-target-aws.nix") ]
  in case env of
    Staging      -> EnvSettings
      { envDeployerUser      = "staging"
      , envDefaultConfigurationKey = "testnet_staging_full"
      , envDefaultConfig     = "staging-testnet.yaml"
      , envDefaultTopology   = "topology-staging.yaml"
      , envDeploymentFiles   = [ (Nodes,          All, "deployments/security-groups.nix")
                               , (Explorer,       All, "deployments/security-groups.nix")
                               , (ReportServer,   All, "deployments/security-groups.nix")
                               , (Nodes,          All, "deployments/cardano-nodes-env-staging.nix")
                               , (Explorer,       All, "deployments/cardano-explorer-env-staging.nix")
                               , (ReportServer,   All, "deployments/report-server-env-staging.nix")
                               , (Faucet,         All, "deployments/faucet-env-staging.nix")
                               , (Infra,          All, "deployments/infrastructure-env-staging.nix")
                               ] <> deplAgnosticFiles}
    Production  -> EnvSettings
      { envDeployerUser      = "live-production"
      , envDefaultConfigurationKey = "testnet_public_full"
      , envDefaultConfig     = "production-testnet.yaml"
      , envDefaultTopology   = "topology-production.yaml"
      , envDeploymentFiles   = [ (Nodes,          All, "deployments/security-groups.nix")
                               , (Explorer,       All, "deployments/security-groups.nix")
                               , (ReportServer,   All, "deployments/security-groups.nix")
                               , (Nodes,          All, "deployments/cardano-nodes-env-production.nix")
                               , (Explorer,       All, "deployments/cardano-explorer-env-production.nix")
                               , (ReportServer,   All, "deployments/report-server-env-production.nix")
                               , (Infra,          All, "deployments/infrastructure-env-production.nix")
                               ] <> deplAgnosticFiles}
    Development -> EnvSettings
      { envDeployerUser      = "staging"
      , envDefaultConfigurationKey = "devnet"
      , envDefaultConfig     = "config.yaml"
      , envDefaultTopology   = "topology-development.yaml"
      , envDeploymentFiles   = [ (Nodes,          All, "deployments/cardano-nodes-env-development.nix")
                               , (Explorer,       All, "deployments/cardano-explorer-env-development.nix")
                               , (ReportServer,   All, "deployments/report-server-env-development.nix")
                               , (Faucet,         All, "deployments/faucet-env-development.nix")
                               ] <> deplAgnosticFiles}
    Any -> error "envSettings called with 'Any'"

selectDeployer :: Environment -> [Deployment] -> NodeName
selectDeployer Staging   delts | elem Nodes delts = "iohk"
                               | otherwise        = "cardano-deployer"
selectDeployer _ _                                = "cardano-deployer"
