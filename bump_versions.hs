#!/usr/bin/env stack
-- stack --install-ghc runghc --package turtle

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

import Turtle
import Prelude hiding (FilePath, log)

import qualified Data.Yaml as Yaml

import qualified Control.Foldl as Fold

import Data.Text (pack, Text)
import Data.Text.Lazy (toStrict)
import qualified Data.Text as T
import Data.Tuple.Select

import GHC.Generics

import System.Console.ANSI

coloredPrint :: Color -> Text -> IO ()
coloredPrint color line = do
  setSGR [SetColor Foreground Vivid color]
  printf s line
  setSGR [Reset]

data Part = API | Project
data Level = App | Major | Minor | Fix | Doc
data Mode = PR | Commit

instance Show Mode where
  show PR = "Pull request"
  show Commit = "Single commit"

data Paths = Paths {
  -- Path to swagger file of API
  swaggerFileName :: Maybe Text
  } deriving (Show, Generic)

instance Yaml.FromJSON Paths

loadPaths :: IO Paths
loadPaths = do
  ms <- Yaml.decodeFileEither "./paths"
  case ms of
    Left err -> error (show err)
    Right paths -> return paths

showText :: Show a => a -> Text
showText = pack . show

changelogFile :: Text
changelogFile = "CHANGELOG.md"

apiChangelogFile :: Text
apiChangelogFile = "API_CHANGELOG.md"

checkChangelogs :: Bool
checkChangelogs = True

latestGitTag :: Text
latestGitTag = "git describe --tags origin/master"

currentVersion :: IO Text
currentVersion = do
  ver <- strict $ inshell (latestGitTag <> " | cut -c 2-") empty
  return $ T.stripEnd ver

levelFromText :: Text -> Level
levelFromText "app" = App
levelFromText "App" = App
levelFromText "APP" = App
levelFromText "major" = Major
levelFromText "Major" = Major
levelFromText "MAJOR" = Major
levelFromText "minor" = Minor
levelFromText "Minor" = Minor
levelFromText "MINOR" = Minor
levelFromText "fix" = Fix
levelFromText "Fix" = Fix
levelFromText "FIX" = Fix
levelFromText "doc" = Doc
levelFromText "Doc" = Doc
levelFromText "DOC" = Doc
levelFromText _ = error "Unsupported level of changes. See supported with -h or --help."

bumpPackage :: Text -> Text -> IO ()
bumpPackage version packageName = do
  printf ("- Updating version for "%s%"\n") packageName
  stdout (inproc "sed" ["-i", "-r", expr, file] empty)
  where
    packageFile = fromText packageName
    file = format fp $ packageFile </> packageFile <.> "cabal"
    expr = "s/(^version:[^0-9]*)[0-9][0-9.]*/\\1" <> version <> "/"

bumpPackages :: Text -> [Text] -> IO ()
bumpPackages version packages = do
  curVersion <- currentVersion
  printf ("Version: "%s%" -> ") curVersion
  coloredPrint Yellow (version <> "\n")

  printf ("Updating packages version to "%s%"\n") version
  mapM_ (bumpPackage version) packages

changelogIsUp :: Text -> Mode -> Part -> Text -> IO Bool
changelogIsUp item mode part message = do
  grepLen <- case part of
    Project -> fold (inproc "grep" [item, changelogFile] empty) Fold.length
    API -> fold (inproc "grep" [item, apiChangelogFile] empty) Fold.length
  case grepLen of
    0 -> do
      printf ("- "%s%" ") (showText mode)
      coloredPrint Cyan item
      case part of
        Project -> printf (" id missing in changelog: "%s%".\n") message
        API -> printf (" id missing in API changelog: "%s%".\n") message
      return False
    _ -> return True

commitMessage :: Mode -> Text -> IO Text
commitMessage _ "" = return ""
commitMessage mode commit = do
  raw <- strict $ inproc "grep" ["^\\s"] $
                    inproc "sed" ["-n", sedString] $
                      inproc "git" ["show", commit] empty
  return $ T.stripEnd $ T.stripStart raw
  where
    sedString = case mode of
      PR -> "8p"
      Commit -> "5p"

gitLatestHistory :: Bool -> IO Text
gitLatestHistory start = do
  tmpFile <- strict $ inproc "mktemp" [] empty
  case start of
    False -> liftIO $ append (process tmpFile) $ inproc "grep" ["-v", "Merge branch"] (inshell history empty)
    True  -> liftIO $ append (process tmpFile) $
      inproc "grep" ["-v", "Merge branch"] (inproc "git" ["log", "--oneline", "--first-parent"] empty)
  return $ T.stripEnd tmpFile
  where
    process = fromText . T.stripEnd
    history = "git log --oneline --first-parent $( " <> latestGitTag <> " )..HEAD"

checkApiChangelogF :: Bool -> Text -> IO Bool
checkApiChangelogF start swaggerFile = do
  printf ("Checking "%s%"\n") apiChangelogFile
  
  history <- gitLatestHistory start

  commits <- strict $ inproc "egrep" ["-o", "^[0-9a-f]+", history] empty
  
  flags <- mapM (eval history) (T.split (== '\n') (T.stripEnd commits))
  return $ foldr1 (&&) flags
  where
    eval hist commit = do
      linePresent <- fold
        (inproc "grep" [swaggerFile]
          (inproc "git" ["show", "--stat", commit] empty))
        Fold.length
      case linePresent of
        0 -> return True
        _ -> do
          pull <- strict $
            inproc "egrep" ["-o", "#[0-9]+"] $
              inproc "egrep" ["-o", "pull request #[0-9]+"] $
                inproc "grep" [commit, hist] empty
          case T.length pull of
            0 -> do
              message <- commitMessage Commit commit
              changelogIsUp commit Commit API message
            _ -> do
              message <- commitMessage PR commit
              changelogIsUp (T.stripEnd pull) PR API message

checkChangelogF :: Bool -> IO Bool
checkChangelogF start = do
  printf ("Checking "%s%"\n") changelogFile
  
  history <- gitLatestHistory start
  
  pullCommits <- strict $
    inproc "egrep" ["-o", "^[0-9a-f]+"] (inproc "egrep" [pullExpr, history] empty)
  pulls <- strict $
    inproc "egrep" ["-o", "#[0-9]+"] (inproc "egrep" ["-o", pullExpr, history] empty)
  singles <- strict $
    inproc "egrep" ["-o", "^[0-9a-f]+"] (inproc "egrep" ["-o", singleExpr, history] empty)
  
  pullHeaders <- mapM (commitMessage PR) (map T.stripEnd (T.split (== '\n') pullCommits))
  singleHeaders <- mapM (commitMessage Commit) (map T.stripEnd (T.split (== '\n') singles))
  flagsPR <- mapM (\(i,m) -> changelogIsUp i PR Project m) (zip (T.split (== '\n') pulls) pullHeaders)
  flagsCommit <- mapM (\(i, m) -> changelogIsUp i Commit Project m) (zip (T.split (== '\n') singles) singleHeaders)
  return $ foldr1 (&&) (flagsPR ++ flagsCommit)
  where
    pullExpr = "pull request #[0-9]+"
    singleExpr = "^[0-9a-f]+\\s[^(Merge)]"

generateVersion :: Level -> IO Text
generateVersion lev = do
  current <- currentVersion
  return $ bump current
  where
    tuplify :: [Int] -> (Int, Int, Int, Int, Int)
    tuplify [] = (0,0,0,0,0)
    tuplify [a1] = (a1,0,0,0,0)
    tuplify [a1,a2] = (a1,a2,0,0,0)
    tuplify [a1,a2,a3] = (a1,a2,a3,0,0)
    tuplify [a1,a2,a3,a4] = (a1,a2,a3,a4,0)
    tuplify [a1,a2,a3,a4,a5] = (a1,a2,a3,a4,a5)
    tuplify (a1:a2:a3:a4:a5:_) = (a1,a2,a3,a4,a5)

    delimited :: Text -> (Int, Int, Int, Int, Int)
    delimited ver = tuplify $ map (read . T.unpack) (T.split (=='.') ver)
    
    bump :: Text -> Text
    bump v = T.intercalate "." $ map showText $ case lev of
      App -> [firstD v + 1, 0]
      Major -> [firstD v, secondD v + 1, 0]
      Minor -> [firstD v, secondD v, thirdD v + 1, 0]
      Fix -> [firstD v, secondD v, thirdD v, fourthD v + 1, 0]
      Doc -> [firstD v, secondD v, thirdD v, fourthD v, fifthD v + 1]
    
    firstD v  = sel1 $ delimited v
    secondD v = sel2 $ delimited v
    thirdD v  = sel3 $ delimited v
    fourthD v = sel4 $ delimited v
    fifthD v  = sel5 $ delimited v

parser :: Parser (Maybe Text, Maybe Text, Bool, Bool, Bool)
parser = (,,,,) <$> optional (optText "packages" 'p' "List of packages to bump.")
                <*> optional (optText "level" 'l' "Level of changes.")
                <*> switch  "no-check"  'c' "Do not check changelogs."
                <*> switch  "from-bc"  'e' "Check changelogs from start of project."
                <*> switch  "force"  'f' "Bump version even if changelogs are outdated. Cannot be mixed with -c."

welcome :: Description
welcome = Description $ "---\n"
        <> "This script can check your changelogs and bump versions in project.\n"
        <> "It assumes to be run in root directory of project and that changelog is here.\n"
        <> "You can specify these levels of changes: app, major, minor, fix, doc.\n"
        <> "It can infer version from changelog.\n"
        <> "But it will refuse to do it if it's not sure changelogs are up to date."

processChecks :: Bool -> Bool -> Paths -> Bool -> IO ()
processChecks True _ _ _ = coloredPrint Yellow "WARNING: skipping checks for changelog.\n"
processChecks False start paths force = do
  case start of
    True -> echo "Checking changelogs from start of project"
    False -> return ()
  upToDate <- checkChangelogF start
  case upToDate of
    False -> coloredPrint Yellow ("WARNING: " <> changelogFile <> " is out of date.\n")
    True -> coloredPrint Green (changelogFile <> " is up to date.\n")
  apiUpToDate <- case swaggerFileName paths of
    Nothing -> do
      coloredPrint Yellow "Do not check API changelog, no swagger file added to ./paths.\n"
      return True
    Just file -> checkApiChangelogF start file
  case apiUpToDate of
    False -> coloredPrint Yellow ("WARNING: " <> apiChangelogFile <> " is out of date.\n")
    True -> coloredPrint Green $ (apiChangelogFile<>" is up to date.\n")
  case apiUpToDate && upToDate of
    False -> do
      coloredPrint Red "ERROR: some changelogs are not up-to-date. Use -c or --no-check options if you want to ignore changelog checks.\n"
      case force of
        False -> exit ExitSuccess
        True -> return ()
    True -> return ()

generateVersionByChangelog :: Bool -> IO Text
generateVersionByChangelog True = do
  coloredPrint Yellow "You are running it with no explicit version modifiers and changelog checks. It can result in anything. Please retry.\n"
  exit ExitSuccess
generateVersionByChangelog False = do
  major <- fold (inproc "grep" ["Major changes"] unreleased) Fold.length
  minor <- fold (inproc "grep" ["Minor changes"] unreleased) Fold.length
  fixes <- fold (inproc "grep" ["Fixes"] unreleased) Fold.length
  docs  <- fold (inproc "grep" ["Docs"] unreleased) Fold.length
  curVersion <- currentVersion
  
  case major of
    0 -> case minor of
      0 -> case fixes of
        0 -> case docs of
          0 -> do
            coloredPrint Yellow ("WARNING: keep old version since " <> changelogFile <> " apparently does not contain any new entries.\n")
            return curVersion
          _ -> generateVersion Doc
        _ -> generateVersion Fix
      _ -> generateVersion Minor
    _ -> generateVersion Major
  
  where
    expr =  "/^[0-9]\\.[0-9]/q"
    unreleased = (inproc "sed" [expr, changelogFile] empty)

main :: IO ()
main = do
  (packages, packageLev, ignoreChecks, fromStart, force) <- options welcome parser

  paths <- loadPaths

  cd ".."

  processChecks ignoreChecks fromStart paths force

  newVersion <- case packageLev of
    Nothing -> generateVersionByChangelog ignoreChecks
    Just lev -> generateVersion (levelFromText lev)

  case packages of
    Just project -> bumpPackages newVersion (T.split (==' ') project)
    Nothing -> case ignoreChecks of
      True  -> coloredPrint Yellow "WARNING: no packages specified.\n"
      False -> coloredPrint Yellow "WARNING: no packages specified, so only check changelogs.\n"
