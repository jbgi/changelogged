{-# LANGUAGE OverloadedStrings #-}
module Changelogged.Common.Utils.Pure where

import qualified System.Process                   as Proc

import           Data.Aeson

import           Data.Monoid                      ((<>))
import           Data.Maybe                       (fromMaybe)
import           Data.Text                        (Text)
import qualified Data.Text                        as Text
import           Prelude                          hiding (FilePath)

import           Data.Char
import           Data.List

import           Filesystem.Path.CurrentOS        (FilePath, encodeString)

import Changelogged.Common.Types.Common

changeloggedVersion :: Version
changeloggedVersion = Version "0.3.0"

prettyPossibleValues :: Show a => [a] -> String
prettyPossibleValues xs = case reverse xs of
  []  -> "none"
  [y] -> prettyValue y
  (y:ys) -> intercalate ", " (map prettyValue (reverse ys)) <> " or " <> prettyValue y
  where
    prettyValue v = "'" <> hyphenate (show v) <> "'"

-- |
-- >>> availableLevels
-- [App,Major,Minor,Fix,Doc]
availableLevels :: [Level]
availableLevels = [minBound..maxBound]

-- |
-- >>> availableLevelsStr
-- "'app', 'major', 'minor', 'fix' or 'doc'"
availableLevelsStr :: String
availableLevelsStr = prettyPossibleValues availableLevels

-- | Maximum in list ordered by length.
maxByLen :: [Text] -> Maybe Text
maxByLen [] = Nothing
maxByLen hs = Just $ foldl1 (\left right -> if Text.length left > Text.length right then left else right) hs

-- |'@fromJust@' function with custom error message.
-- should be used in cases where 'Nothing' cannot happen with consistent input data.
fromJustCustom :: String -> Maybe a -> a
fromJustCustom msg Nothing = error msg
fromJustCustom _ (Just a)  = a

-- I leave tuple here cause it's all functions for internal usage only (tuplify, delimited, bump).
tuplify :: [Int] -> (Int, Int, Int, Int, Int)
tuplify []                 = (0,0,0,0,0)
tuplify [a1]               = (a1,0,0,0,0)
tuplify [a1,a2]            = (a1,a2,0,0,0)
tuplify [a1,a2,a3]         = (a1,a2,a3,0,0)
tuplify [a1,a2,a3,a4]      = (a1,a2,a3,a4,0)
tuplify [a1,a2,a3,a4,a5]   = (a1,a2,a3,a4,a5)
tuplify (a1:a2:a3:a4:a5:_) = (a1,a2,a3,a4,a5)

delimited :: Text -> (Int, Int, Int, Int, Int)
delimited ver = tuplify $ map (read . Text.unpack) (Text.split (=='.') ver)

-- FIXME: Refactor and make correspondent with PVP.
bump :: (Int, Int, Int, Int, Int) -> Level -> Text
bump (app, major, minor, fix, doc) lev = Text.intercalate "." $ map showText $ case lev of
  App   -> [app + 1, 0]
  Major -> [app, major + 1, 0]
  Minor -> [app, major, minor + 1]
  Fix   -> [app, major, minor, fix + 1]
  Doc   -> [app, major, minor, fix, doc + 1]

showPath :: FilePath -> Text
showPath = Text.pack . encodeString

showText :: Show a => a -> Text
showText = Text.pack . show

splitCamelWords :: String -> [String]
splitCamelWords = reverse . splitWordsReversed . reverse

splitWordsReversed :: String -> [String]
splitWordsReversed [] = []
splitWordsReversed rs
  | null ls   = reverse us : splitWordsReversed urs
  | otherwise = case lrs of
                  []     -> [reverse ls]
                  (c:cs) -> (c : reverse ls) : splitWordsReversed cs
  where
    (ls, lrs) = span (not . isBorder) rs
    (us, urs) = span isBorder rs
    isBorder c = isUpper c || isDigit c

-- | Convert @CamelCase@ to @snake_case@.
--
-- >>> toSnakeCase "VersionFile"
-- "version_file"
-- >>> toSnakeCase "Config"
-- "config"
toSnakeCase :: String -> String
toSnakeCase = map toLower . intercalate "_" . splitCamelWords

-- |
--
-- >>> hyphenate "VersionFile"
-- "version-file"
-- >>> hyphenate "Config"
-- "config"
hyphenate :: String -> String
hyphenate = map toLower . intercalate "-" . splitCamelWords

jsonDerivingModifier :: String -> Options
jsonDerivingModifier prefix = defaultOptions {
  fieldLabelModifier = toSnakeCase . drop (length prefix)
  }

extractProjectNameFromUrl :: Link -> Text
extractProjectNameFromUrl (Link url) = Text.takeWhileEnd (/= '/') . fromMaybe url $ Text.stripSuffix ".git" url

templateProcess :: Proc.CreateProcess
templateProcess = Proc.CreateProcess
  { Proc.cmdspec = (Proc.RawCommand "echo" ["Template process on the run"])
  , Proc.cwd = Nothing
  , Proc.env = Nothing
  , Proc.std_in = Proc.Inherit
  , Proc.std_out = Proc.Inherit
  , Proc.std_err = Proc.Inherit
  , Proc.close_fds = True
  , Proc.create_group = False
  , Proc.delegate_ctlc = True
  , Proc.detach_console = True
  , Proc.create_new_console = True
  , Proc.new_session = True
  , Proc.child_group = Nothing
  , Proc.child_user = Nothing
  , Proc.use_process_jobs = False
  }
