module Loc
  ( Loc (..),
    rootLoc,
    renderLoc,
  )
where

data Loc = Loc
  { locFile :: !FilePath,
    locLine :: !Int
  }
  deriving (Show, Eq, Ord)

rootLoc :: Int -> Loc
rootLoc = Loc ""

renderLoc :: Loc -> String
renderLoc (Loc f n)
  | null f = "line " ++ show n
  | otherwise = f ++ ":" ++ show n
