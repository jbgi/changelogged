{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
module Changelogged.Config where

import Data.Aeson
import Data.Monoid ((<>))
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Yaml as Yaml

import qualified Turtle

import Changelogged.Options

data Config = Config
  { configChangelogs    :: [ChangelogConfig]
  , configIgnoreCommits :: Maybe [Text]
  , configBranch        :: Maybe Text
  } deriving Eq

data ChangelogConfig = ChangelogConfig
  { changelogChangelog    :: Turtle.FilePath
  , changelogWatchFiles   :: Maybe [Turtle.FilePath]
  , changelogIgnoreFiles  :: Maybe [Turtle.FilePath]
  , changelogVersionFiles :: Maybe [VersionFile]
  } deriving Eq

data VersionFile = VersionFile
  { versionFilePath :: Turtle.FilePath
  , versionFileVersionPattern :: Text
  } deriving (Show, Eq)

instance FromJSON Config where
  parseJSON = withObject "Config" $ \o -> Config
    <$> o .:  "changelogs"
    <*> o .:? "ignore_commits"
    <*> o .:? "branch"

instance FromJSON ChangelogConfig where
  parseJSON = withObject "ChangelogConfig" $ \o -> ChangelogConfig
    <$> (fromString <$> o .:  "changelog")
    <*> (fmap (map fromString) <$> o .:? "watch_files")
    <*> (fmap (map fromString) <$> o .:? "ignore_files")
    <*> o .:? "version_files"

instance FromJSON VersionFile where
  parseJSON = withObject "VersionFile" $ \o -> VersionFile
    <$> (fromString <$> o .: "path")
    <*> o .: "version_pattern"

defaultConfig :: Config
defaultConfig = Config
  { configChangelogs    = pure ChangelogConfig
      { changelogChangelog    = "ChangeLog.md"
      , changelogWatchFiles   = Nothing  -- watch everything
      , changelogIgnoreFiles  = Nothing  -- ignore nothing
      , changelogVersionFiles = Just [VersionFile "package.yaml" "version:"]
      }
  , configIgnoreCommits = Nothing
  , configBranch = Nothing
  }

loadConfig :: FilePath -> Appl (Maybe Config)
loadConfig path = do
  ms <- liftIO $ Yaml.decodeFileEither path
  return $ case ms of
    Left _wrong -> Nothing
    Right paths -> Just paths

ppConfig :: Config -> Text
ppConfig Config{..} = mconcat
  [ "Main branch (with version tags)" ?: configBranch
  , "Ignored commits" ?: (Text.pack . show . length <$> configIgnoreCommits)
  , "Changelogs" !: formatItems Turtle.fp (map changelogChangelog configChangelogs)
  ]
  where
    formatItems fmt
      = ("\n" <>)
      . Text.unlines
      . map (\x -> "- " <> Turtle.format fmt x)

    name !: val = name <> ": " <> val <> "\n"

    _    ?: Nothing = ""
    name ?: Just val = name !: val
