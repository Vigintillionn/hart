import Test.Hspec
import qualified Test.AssemblerSpec
import qualified Test.CSRSpec
import qualified Test.DebuggerSpec
import qualified Test.DocSpec
import qualified Test.ExecutionSpec
import qualified Test.ExtensionSpec
import qualified Test.KernelSpec
import qualified Test.LinkerSpec
import qualified Test.ParserSpec
import qualified Test.PreprocessSpec
import qualified Test.RpcSpec
import qualified Test.TrapSpec
import qualified Test.WireSpec

main :: IO ()
main = hspec $ do
    describe "Assembler" Test.AssemblerSpec.spec
    describe "Parser" Test.ParserSpec.spec
    describe "Preprocess" Test.PreprocessSpec.spec
    describe "Linker" Test.LinkerSpec.spec
    describe "Extension" Test.ExtensionSpec.spec
    describe "Execution" Test.ExecutionSpec.spec
    describe "CSR" Test.CSRSpec.spec
    describe "Kernel" Test.KernelSpec.spec
    describe "Trap" Test.TrapSpec.spec
    describe "Debugger" Test.DebuggerSpec.spec
    describe "Wire" Test.WireSpec.spec
    describe "Doc" Test.DocSpec.spec
    describe "RPC (integration)" Test.RpcSpec.spec
