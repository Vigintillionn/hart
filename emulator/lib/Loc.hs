module Loc
  ( Loc (..),
    rootLoc,
    renderLoc,
  )
where

-- | where a source line came from: the translation unit (root buffer) it
-- belongs to, and the file and line it was written in. Unit and file differ
-- only inside an @.include@d file, whose lines belong to the includer's unit.
data Loc = Loc
  { locUnit :: !FilePath,
    locFile :: !FilePath,
    locLine :: !Int
  }
  deriving (Show, Eq, Ord)

rootLoc :: Int -> Loc
rootLoc = Loc "" ""

renderLoc :: Loc -> String
renderLoc (Loc _ f n)
  | null f = "line " ++ show n
  | otherwise = f ++ ":" ++ show n
