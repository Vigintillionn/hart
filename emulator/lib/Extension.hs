module Extension
  ( Extension (..),
    ExtensionSet,
    allExtensions,
    baseExtensions,
    defaultExtensions,
    mkExtensionSet,
    withRequirements,
    isEnabled,
    extensionCode,
    readExtensionCode,
    ExtensionInfo (..),
    extensionInfo,
    extensionCatalogue,
  )
where

import Data.List (foldl')
import Data.Set (Set)
import Data.Set qualified as Set

data Extension
  = -- | RV32I - base integer set (mandatory)
    IExt
  | -- | RV32M - integer multiply / divide
    MExt
  | -- | Zicond - integer conditional operations
    ZicondExt
  | -- | Zicsr - control and status register access
    ZicsrExt
  | -- | Zba - address generation
    ZbaExt
  | -- | Zbb - basic bit manipulation
    ZbbExt
  | -- | Zbs - single-bit operations
    ZbsExt
  deriving (Show, Eq, Ord, Enum, Bounded)

type ExtensionSet = Set Extension

allExtensions :: ExtensionSet
allExtensions = Set.fromList extensionCatalogue

baseExtensions :: ExtensionSet
baseExtensions = Set.fromList [e | e <- extensionCatalogue, extMandatory (extensionInfo e)]

defaultExtensions :: ExtensionSet
defaultExtensions = allExtensions

mkExtensionSet :: [Extension] -> ExtensionSet
mkExtensionSet xs = Set.union baseExtensions (withRequirements (extRequires . extensionInfo) xs)

-- | The given extensions plus everything they transitively require.
withRequirements :: (Ord a) => (a -> [a]) -> [a] -> Set a
withRequirements requirementsOf = foldl' include Set.empty
  where
    include enabled x
      | Set.member x enabled = enabled
      | otherwise = foldl' include (Set.insert x enabled) (requirementsOf x)

isEnabled :: Extension -> ExtensionSet -> Bool
isEnabled = Set.member

-- | The canonical single-letter ISA code (the letter in @RV32IM@).
extensionCode :: Extension -> String
extensionCode = extCode . extensionInfo

readExtensionCode :: String -> Maybe Extension
readExtensionCode c = lookup c [(extensionCode e, e) | e <- extensionCatalogue]

data ExtensionInfo = ExtensionInfo
  { extCode :: String,
    extName :: String,
    extSummary :: String,
    extMandatory :: Bool,
    extRequires :: [Extension]
  }
  deriving (Show, Eq)

extensionInfo :: Extension -> ExtensionInfo
extensionInfo IExt =
  ExtensionInfo
    { extCode = "I",
      extName = "Base Integer",
      extSummary =
        "Core integer arithmetic, control flow, loads/stores and system "
          ++ "instructions. Mandatory - always enabled.",
      extMandatory = True,
      extRequires = []
    }
extensionInfo MExt =
  ExtensionInfo
    { extCode = "M",
      extName = "Integer Multiply / Divide",
      extSummary =
        "Hardware multiplication, division and remainder "
          ++ "(mul, mulh, mulhsu, mulhu, div, divu, rem, remu).",
      extMandatory = False,
      extRequires = []
    }
extensionInfo ZicondExt =
  ExtensionInfo
    { extCode = "Zicond",
      extName = "Integer Conditional",
      extSummary =
        "Conditional zeroing for branchless selects "
          ++ "(czero.eqz, czero.nez).",
      extMandatory = False,
      extRequires = []
    }
extensionInfo ZicsrExt =
  ExtensionInfo
    { extCode = "Zicsr",
      extName = "Control and Status Registers",
      extSummary =
        "Atomic read/modify/write access to control and status registers "
          ++ "(csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci).",
      extMandatory = False,
      extRequires = []
    }
extensionInfo ZbaExt =
  ExtensionInfo
    { extCode = "Zba",
      extName = "Address Generation",
      extSummary =
        "Shift-and-add for indexing arrays of 2, 4 and 8 byte elements "
          ++ "(sh1add, sh2add, sh3add).",
      extMandatory = False,
      extRequires = []
    }
extensionInfo ZbbExt =
  ExtensionInfo
    { extCode = "Zbb",
      extName = "Basic Bit Manipulation",
      extSummary =
        "Logic with negate, bit counting, min/max, sign and zero extension, "
          ++ "rotates and byte reversal (andn, clz, cpop, max, sext.b, rol, rev8, ...).",
      extMandatory = False,
      extRequires = []
    }
extensionInfo ZbsExt =
  ExtensionInfo
    { extCode = "Zbs",
      extName = "Single-Bit Operations",
      extSummary =
        "Clear, set, invert or extract one bit "
          ++ "(bclr, bset, binv, bext and their immediate forms).",
      extMandatory = False,
      extRequires = []
    }

extensionCatalogue :: [Extension]
extensionCatalogue = [minBound .. maxBound]
