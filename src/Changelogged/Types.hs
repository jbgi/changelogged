{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
module Changelogged.Types where

import Data.Aeson
import Data.Text (Text)
import GHC.Generics (Generic)

import qualified Filesystem.Path.CurrentOS as Path

type Variable = Text
type Key = Text

instance FromJSON Path.FilePath where
  parseJSON = fmap Path.decodeString . parseJSON

-- |Level of changes to bump to.
data Level = App | Major | Minor | Fix | Doc
  deriving (Generic, Show, Enum, Bounded, ToJSON)

-- |Available altenative actions
data Action = UpdateChangelogs | BumpVersions
  deriving (Generic, Eq, Show, Enum, Bounded, ToJSON)

-- |Type of entry in git history.
data Mode = PR | Commit deriving (Eq)

instance Show Mode where
  show PR = "Pull request"
  show Commit = "Commit"

data WarningFormat
  = WarnSimple
  | WarnSuggest
  deriving (Generic, Eq, Enum, Bounded, ToJSON)

instance Show WarningFormat where
  show WarnSimple  = "simple"
  show WarnSuggest = "suggest"
