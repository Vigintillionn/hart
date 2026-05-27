import Test.Hspec
import qualified Test.AssemblerSpec

main :: IO ()
main = hspec $ do
    describe "Assembler" Test.AssemblerSpec.spec
