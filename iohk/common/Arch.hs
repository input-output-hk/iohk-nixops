{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}

module Arch
  ( Arch(..)
  , ArchMap
  , ApplicationVersionKey
  , formatArch
  , archMap
  , mkArchMap
  , archMapToList
  , archMapFromList
  , lookupArch
  , idArchMap
  , archMapEach
  ) where

import qualified Data.Aeson            as AE
import           Data.Aeson
import           Data.Text              (Text)
import           GHC.Generics

-- * Arch
data Arch = Linux64 | Mac64 | Win64 deriving (Show, Read, Eq, Generic)

instance FromJSON Arch
instance ToJSON Arch

type ApplicationVersionKey = Arch -> Text

formatArch :: Arch -> Text
formatArch Linux64 = "Linux"
formatArch Mac64 = "macOS"
formatArch Win64 = "Windows"

-- | A map of values indexed by Arch.
data ArchMap a = ArchMap { linux64 :: !a, mac64 :: !a, win64 :: !a }
  deriving (Show, Read, Eq, Generic, Functor, Foldable, Traversable)

instance Applicative ArchMap where
  pure a = ArchMap a a a
  ArchMap f g h <*> ArchMap l m w = ArchMap (f l) (g m) (h w)

-- | Construct an arch map using fixed values.
mkArchMap :: a -- ^ Linux value
          -> a -- ^ macOS value
          -> a -- ^ Windows value
          -> ArchMap a
mkArchMap l m w = ArchMap l m w

-- | Construct an arch map with a lookup function.
archMap :: (Arch -> a) -> ArchMap a
archMap get = ArchMap (get Linux64) (get Mac64) (get Win64)

-- | Get the value for a given arch.
lookupArch :: Arch -> ArchMap a -> a
lookupArch Linux64 (ArchMap a _ _) = a
lookupArch Mac64   (ArchMap _ a _) = a
lookupArch Win64   (ArchMap _ _ a) = a

-- | Returns the map as a list of (Arch, value) pairs.
archMapToList :: ArchMap a -> [(Arch, a)]
archMapToList (ArchMap l m w) = [(Linux64, l), (Mac64, m), (Win64, w)]

idArchMap :: ArchMap Arch
idArchMap = ArchMap Linux64 Mac64 Win64

-- | Returns the map as a list of (Arch, value) pairs, where not all
-- arches are present.
archMapToList' :: ArchMap (Maybe a) -> [(Arch, a)]
archMapToList' am = [(a, v) | (a, Just v) <- archMapToList am]

-- | Construct an arch map from a list of pairs.
archMapFromList :: [(Arch, a)] -> ArchMap (Maybe a)
archMapFromList = build (pure Nothing)
  where
    build am [] = am
    build am (e:es) = build (add e am) es
    add (Linux64, l) (ArchMap _ m w) = ArchMap (Just l) m w
    add (Mac64, m)   (ArchMap l _ w) = ArchMap l (Just m) w
    add (Win64, w)   (ArchMap l m _) = ArchMap l m (Just w)

instance FromJSON a => FromJSON (ArchMap a) where
  parseJSON = AE.withObject "ArchMap" $ \o ->
    mkArchMap <$> o .: "linux" <*> o .: "darwin" <*> o .: "windows"

instance ToJSON a => ToJSON (ArchMap a) where
  toJSON am = AE.object [ "linux" .= lookupArch Linux64 am
                        , "darwin" .= lookupArch Mac64 am
                        , "windows" .= lookupArch Win64 am ]

-- | Run an action for each arch. The difference between this and
-- 'fmap' is that the action receives an arch parameter.
archMapEach :: Applicative f => (Arch -> a -> f b) -> ArchMap a -> f (ArchMap b)
archMapEach f (ArchMap l m w) = ArchMap <$> f Linux64 l <*> f Mac64 m <*> f Win64 w
