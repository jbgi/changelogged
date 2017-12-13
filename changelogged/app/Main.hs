module Main where

import Prelude hiding (FilePath)
import Turtle
import qualified Data.HashMap.Strict as HM
import Data.Maybe (fromMaybe)

import System.Console.ANSI (Color(..))

import CheckLog.Check
import Bump.API
import Bump.Project
import Types
import Git
import Options
import Utils
import Pure (showPath, fromJustCustom)
import Settings

--printf ("Version: "%s%" -> ") curVersion
--coloredPrint Yellow (version <> "\n")

commonMain :: Paths -> Options -> Git -> IO ()
commonMain paths opts@Options{..} git = do
  coloredPrint Green ("Checking " <> showPath (taggedLogPath $ chLog paths) <> " and creating it if missing.\n")
  touch $ taggedLogPath (chLog paths)

  bump <- checkChangelogWrap opts git optNoCheck (chLog paths)

  when (bump && not optNoBump) $ do
    newVersion <- case optPackagesLevel of
      Nothing -> generateVersionByChangelog optNoCheck (taggedLogPath $ chLog paths) (gitRevision git)
      Just lev -> Just <$> generateVersion lev (gitRevision git)
  
    case newVersion of
      Nothing -> return ()
      Just version -> case HM.lookup "main" (defaultedEmpty (versioned paths)) of
        Just files -> mapM_ (bumpPart version) files
        Nothing -> coloredPrint Yellow "WARNING: no files to bump project version in specified.\n"
  where
    chLog cfg = HM.lookupDefault (TaggedLog "CHANGELOG.md" Nothing) "main"
      (fromMaybe (HM.singleton "main" (TaggedLog "CHANGELOG.md" Nothing)) (changelogs cfg))

apiMain :: Paths -> Options -> Git -> IO ()
apiMain paths opts@Options{..} git = do
  coloredPrint Green ("Checking " <> showPath (taggedLogPath $ chLog paths) <> " and creating it if missing.\n")
  touch $ taggedLogPath (chLog paths)

  bump <- checkChangelogWrap opts git optNoCheck (chLog paths)

  when (bump && not optNoBump) $ do
    newVersion <- case optApiLevel of
      Nothing -> generateLocalVersionByChangelog optNoCheck (chLog paths)
      Just lev -> Just <$> generateLocalVersion lev (fromJustCustom $ taggedLogIndicator $ chLog paths)
  
    case newVersion of
      Nothing -> return ()
      Just version -> case HM.lookup "api" (defaultedEmpty (versioned paths)) of
        Just files -> mapM_ (bumpPart version) files
        Nothing -> coloredPrint Yellow "WARNING: no files to bump API version in specified.\n"
  where
    chLog cfg = HM.lookupDefault (TaggedLog "API_CHANGELOG.md" Nothing) "api"
      (fromMaybe (HM.singleton "api" (TaggedLog "API_CHANGELOG.md" Nothing)) (changelogs cfg))

otherMain :: Paths -> Options -> Git -> IO ()
otherMain paths opts@Options{..} git = do
  mapM_ act (entries (changelogs paths))
  where
    entries :: Maybe (HM.HashMap Text TaggedLog) -> [(Text, TaggedLog)]
    entries (Just a) = HM.toList $ HM.delete "main" $ HM.delete "api" a
    entries Nothing = []
    
    act (key, changelog) = do
      coloredPrint Green ("Checking " <> showPath (taggedLogPath changelog) <> " and creating it if missing.\n")
      touch (taggedLogPath changelog)
    
      bump <- checkChangelogWrap opts git optNoCheck changelog
    
      when (bump && not optNoBump) $ do
        newVersion <- generateLocalVersionByChangelog optNoCheck changelog
      
        case newVersion of
          Nothing -> return ()
          Just version -> case HM.lookup key (defaultedEmpty (versioned paths)) of
            Just files -> mapM_ (bumpPart version) files
            Nothing -> coloredPrint Yellow "WARNING: no files to bump version in specified.\n"

main :: IO ()
main = do
  opts@Options{..} <- options welcome parser

  paths <- loadPaths

  git <- gitData optFromBC

  commonMain paths opts git

  when optWithAPI $ apiMain paths opts git

  when optDifferentChlogs $ otherMain paths opts git
  
  sh $ rm $ gitHistory git
