import Test.Hspec
import qualified Test.AssemblerSpec
import qualified Test.CSRSpec
import qualified Test.ExecutionSpec
import qualified Test.ExtensionSpec
import qualified Test.KernelSpec
import qualified Test.LinkerSpec
import qualified Test.ParserSpec
import qualified Test.TrapSpec

main :: IO ()
main = hspec $ do
    describe "Assembler" Test.AssemblerSpec.spec
    describe "Parser" Test.ParserSpec.spec
    describe "Linker" Test.LinkerSpec.spec
    describe "Extension" Test.ExtensionSpec.spec
    describe "Execution" Test.ExecutionSpec.spec
    describe "CSR" Test.CSRSpec.spec
    describe "Kernel" Test.KernelSpec.spec
    describe "Trap" Test.TrapSpec.spec
