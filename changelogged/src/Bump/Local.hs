module Bump.Local where

import Turtle
import Prelude hiding (FilePath, log)

import Control.Exception
import qualified Control.Foldl as Fold

import Data.Text (Text)

import System.Console.ANSI (Color(..))

import Types
import Utils
import Pure
import Pattern
import Bump.Common

-- |Get current local version.
currentLocalVersion :: TaggedFile -> IO Text
currentLocalVersion TaggedFile{..} = do
  ver <- case extension taggedFilePath of
    Just "json" -> fold (grep (has $ jsonVarGrep taggedFileVariable) (input taggedFilePath)) Fold.head
    Just "hs" -> fold (grep (has $ hsVarGrep taggedFileVariable) (input taggedFilePath)) Fold.head
    Just "cabal" -> fold (grep (has $ cabalVarGrep taggedFileVariable) (input taggedFilePath)) Fold.head
    _ -> throw (PatternMatchFail "Unsupported extension in indicator file. Check config.\n")
  return $ case ver of
    Just realVer -> case versionMatch . lineToText $ realVer of
      Just v -> v
      Nothing -> throw (PatternMatchFail "Given variable doesn't store version. Check config.\n")
    Nothing -> throw (PatternMatchFail "Cannot find given variable in file. Check config.\n")

-- |Generate new local version.
generateLocalVersion :: Level -> TaggedFile -> IO Text
generateLocalVersion lev indicator = do
  current <- currentLocalVersion indicator
  -- This print must not be here but I think it's better than throw current vrsion to main.
  printf ("Version: "%s%" -> ") current
  coloredPrint Yellow (new current <> "\n")
  return (new current)
  where
    new current = bump (delimited current) lev

-- |Infer new local version.
generateLocalVersionByChangelog :: Bool -> TaggedLog -> IO (Maybe Text)
generateLocalVersionByChangelog True _ = do
  coloredPrint Yellow "You are bumping API version with no explicit version modifiers and changelog checks. It can result in anything. Please retry.\n"
  return Nothing
generateLocalVersionByChangelog False TaggedLog{..} = do
  versionedChanges <- getChangelogEntries taggedLogPath
  case versionedChanges of
    Just lev -> Just <$> generateLocalVersion lev (fromJustCustom taggedLogIndicator "No file with current local version specified.")
    Nothing -> do
      coloredPrint Yellow ("WARNING: keep old API version since " <> showPath taggedLogPath <> " apparently does not contain any new entries.\n")
      return Nothing
