module Preprocess
  ( Expanded (..),
    PreprocessError (..),
    IncludeFailure (..),
    Resolver,
    expand,
    expandMany,
    locAt,
    includeTarget,
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Trans.Class (lift)
import Data.Char (isSpace)
import Data.IntMap.Strict qualified as IM
import Data.List (stripPrefix)
import Loc (Loc (..))

-- | a flattened source buffer plus, for each 1-based flattened line, the
-- original 'Loc' it came from
data Expanded = Expanded
  { expSource :: String,
    expLocs :: IM.IntMap Loc
  }
  deriving (Show, Eq)

locAt :: Expanded -> Int -> Loc
locAt ex n = IM.findWithDefault (Loc "" n) n (expLocs ex)

data IncludeFailure
  = -- | the file was searched for but not found
    NotFound
  deriving (Show, Eq)

data PreprocessError
  = -- | the @.include@ site and the path it requested
    IncludeNotFound Loc FilePath
  | -- | the @.include@ site and the path that re-entered an active file
    IncludeCycle Loc FilePath
  deriving (Show, Eq)

type Resolver m = FilePath -> FilePath -> m (Either IncludeFailure (FilePath, String))

expand ::
  (Monad m) => Resolver m -> FilePath -> String -> m (Either PreprocessError Expanded)
expand resolver rootPath rootContent = expandMany resolver [(rootPath, rootContent)]

-- | inline @.include@s across several root buffers and concatenate the results
-- into one translation unit, preserving each line's origin
expandMany ::
  (Monad m) => Resolver m -> [(FilePath, String)] -> m (Either PreprocessError Expanded)
expandMany resolver roots = runExceptT $ do
  pairs <- concat <$> traverse (\(p, c) -> expandPairs resolver [p] p c) roots
  pure
    Expanded
      { expSource = unlines (map snd pairs),
        expLocs = IM.fromList (zip [1 ..] (map fst pairs))
      }

-- | expand one file into @(origin, line)@ pairs. @activ@ is the stack of files
-- currently being expanded, for cycle detection
expandPairs ::
  (Monad m) =>
  Resolver m ->
  [FilePath] ->
  FilePath ->
  String ->
  ExceptT PreprocessError m [(Loc, String)]
expandPairs resolver active path content =
  concat <$> traverse expandLine (zip [1 ..] (lines content))
  where
    expandLine (n, line) =
      let loc = Loc path n
       in case includeTarget line of
            Nothing -> pure [(loc, line)]
            Just req -> do
              outcome <- lift (resolver (parentDir path) req)
              case outcome of
                Left NotFound -> throwError (IncludeNotFound loc req)
                Right (canon, content')
                  | canon `elem` active -> throwError (IncludeCycle loc canon)
                  | otherwise -> expandPairs resolver (canon : active) canon content'

includeTarget :: String -> Maybe FilePath
includeTarget line = case stripPrefix ".include" (dropWhile isSpace line) of
  Just rest@(c : _) | isSpace c -> quoted (dropWhile isSpace rest)
  _ -> Nothing
  where
    quoted ('"' : cs) = case break (== '"') cs of
      (path, '"' : _) | not (null path) -> Just path
      _ -> Nothing
    quoted _ = Nothing

parentDir :: FilePath -> FilePath
parentDir path = case break (== '/') (reverse path) of
  (_, '/' : rest) -> reverse rest
  _ -> ""
