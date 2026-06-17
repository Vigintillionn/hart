module Test.PreprocessSpec (spec) where

import Data.Functor.Identity (Identity (..))
import Data.Map.Strict qualified as Map
import Loc (Loc (..))
import Preprocess
import Test.Hspec

memResolver :: Map.Map FilePath String -> Resolver Identity
memResolver files _dir req =
  Identity $ case Map.lookup req files of
    Just content -> Right (req, content)
    Nothing -> Left NotFound

run :: Map.Map FilePath String -> FilePath -> String -> Either PreprocessError Expanded
run files root content = runIdentity (expand (memResolver files) root content)

expandOK :: Either PreprocessError Expanded -> Expanded
expandOK (Right ex) = ex
expandOK (Left e) = error ("unexpected preprocess error: " ++ show e)

spec :: Spec
spec = do
  describe "includeTarget" $ do
    it "recognises an .include line and extracts the quoted path" $ do
      includeTarget "        .include \"macros.s\"" `shouldBe` Just "macros.s"
      includeTarget ".include \"a/b.s\" # comment" `shouldBe` Just "a/b.s"

    it "ignores non-include lines" $ do
      includeTarget "        li a0, 1" `shouldBe` Nothing
      includeTarget ".included \"x\"" `shouldBe` Nothing
      includeTarget ".include macros.s" `shouldBe` Nothing

  describe "expand" $ do
    it "passes a buffer with no includes through, tagging each line to the root" $ do
      let ex = expandOK (run Map.empty "main.s" "foo\nbar\n")
      expSource ex `shouldBe` "foo\nbar\n"
      locAt ex 1 `shouldBe` Loc "main.s" 1
      locAt ex 2 `shouldBe` Loc "main.s" 2

    it "inlines an included file and keeps each line's true origin" $ do
      -- main line 1 includes `inc`; main line 2 is `foo`
      let files = Map.fromList [("inc", "bar\nbaz\n")]
          ex = expandOK (run files "main.s" ".include \"inc\"\nfoo\n")
      expSource ex `shouldBe` "bar\nbaz\nfoo\n"
      locAt ex 1 `shouldBe` Loc "inc" 1 -- first included line
      locAt ex 2 `shouldBe` Loc "inc" 2
      locAt ex 3 `shouldBe` Loc "main.s" 2 -- line after the include site
    it "expands includes recursively" $ do
      let files =
            Map.fromList
              [ ("a", ".include \"b\"\naa\n"),
                ("b", "bb\n")
              ]
          ex = expandOK (run files "main.s" ".include \"a\"\nend\n")
      expSource ex `shouldBe` "bb\naa\nend\n"
      locAt ex 1 `shouldBe` Loc "b" 1
      locAt ex 2 `shouldBe` Loc "a" 2
      locAt ex 3 `shouldBe` Loc "main.s" 2

    it "reports a missing include at its site" $
      run Map.empty "main.s" ".include \"gone\"\n"
        `shouldBe` Left (IncludeNotFound (Loc "main.s" 1) "gone")

    it "detects an include cycle" $ do
      -- main -> a -> main; `main` must be resolvable for the re-entry to be seen
      let files =
            Map.fromList
              [ ("a", ".include \"main\"\n"),
                ("main", ".include \"a\"\n")
              ]
      run files "main" ".include \"a\"\n"
        `shouldBe` Left (IncludeCycle (Loc "a" 1) "main")
