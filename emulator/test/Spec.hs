import Test.Hspec
import qualified Test.AssemblerSpec
import qualified Test.ExecutionSpec
import qualified Test.ExtensionSpec
import qualified Test.LinkerSpec
import qualified Test.ParserSpec

main :: IO ()
main = hspec $ do
    describe "Assembler" Test.AssemblerSpec.spec
    describe "Parser" Test.ParserSpec.spec
    describe "Linker" Test.LinkerSpec.spec
    describe "Extension" Test.ExtensionSpec.spec
    describe "Execution" Test.ExecutionSpec.spec
