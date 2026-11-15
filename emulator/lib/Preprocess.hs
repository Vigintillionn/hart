module Preprocess
  ( Expanded (..),
    PreprocessError (..),
    IncludeFailure (..),
    Resolver,
    expand,
    expandMany,
    locAt,
    includeTarget,
    includeFault,
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Trans.Class (lift)
import Data.Bifunctor (first)
import Data.Char (isSpace)
import Data.IntMap.Strict qualified as IM
import Data.List (stripPrefix)
import Data.Set qualified as S
import Error (EmulatorError (..))
import Loc (Loc (..))

-- | a flattened source buffer plus, for each 1-based flattened line, the
-- original 'Loc' it came from
data Expanded = Expanded
  { expSource :: String,
    expLocs :: IM.IntMap Loc,
    -- | the root buffers that became translation units, in link order
    expUnits :: [FilePath]
  }
  deriving (Show, Eq)

locAt :: Expanded -> Int -> Loc
locAt ex n = IM.findWithDefault (Loc "" "" n) n (expLocs ex)

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

-- | the typed, located fault a failed @.include@ is reported as
includeFault :: PreprocessError -> EmulatorError
includeFault e = case e of
  IncludeNotFound loc p -> at loc (EIncludeNotFound p)
  IncludeCycle loc p -> at loc (EIncludeCycle p)
  where
    at loc = ELocated (locLine loc) (locFile loc)

type Resolver m = FilePath -> FilePath -> m (Either IncludeFailure (FilePath, String))

expand ::
  (Monad m) => Resolver m -> FilePath -> String -> m (Either PreprocessError Expanded)
expand resolver rootPath rootContent = expandMany resolver [(rootPath, rootContent)]

-- | inline @.include@s across several root buffers and concatenate the
-- results, each root a translation unit of its own, preserving each line's
-- origin. A root that another root includes is not a unit: it is already part
-- of its includer, and linking it again would define its symbols twice. The
-- first root is always kept.
expandMany ::
  (Monad m) => Resolver m -> [(FilePath, String)] -> m (Either PreprocessError Expanded)
expandMany resolver roots = runExceptT $ do
  expanded <- traverse (\(p, c) -> (,) p <$> expandPairs resolver p [p] p c) roots
  let included = S.unions [incs | (_, (incs, _)) <- expanded]
      units = case expanded of
        [] -> []
        entry : rest -> entry : filter ((`S.notMember` included) . fst) rest
      pairs = concat [ls | (_, (_, ls)) <- units]
  pure
    Expanded
      { expSource = unlines (map snd pairs),
        expLocs = IM.fromList (zip [1 ..] (map fst pairs)),
        expUnits = map fst units
      }

-- | expand one file into the set of files it includes (transitively) and its
-- @(origin, line)@ pairs. Every line belongs to the translation unit @unit@
-- (the root buffer); @active@ is the stack of files currently being expanded,
-- for cycle detection
expandPairs ::
  (Monad m) =>
  Resolver m ->
  FilePath ->
  [FilePath] ->
  FilePath ->
  String ->
  ExceptT PreprocessError m (S.Set FilePath, [(Loc, String)])
expandPairs resolver unit active path content =
  mconcat <$> traverse expandLine (zip [1 ..] (lines content))
  where
    expandLine (n, line) =
      let loc = Loc unit path n
       in case includeTarget line of
            Nothing -> pure (S.empty, [(loc, line)])
            Just req -> do
              outcome <- lift (resolver (parentDir path) req)
              case outcome of
                Left NotFound -> throwError (IncludeNotFound loc req)
                Right (canon, content')
                  | canon `elem` active -> throwError (IncludeCycle loc canon)
                  | otherwise ->
                      first (S.insert canon)
                        <$> expandPairs resolver unit (canon : active) canon content'

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
