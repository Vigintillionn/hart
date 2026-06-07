module Extension
  ( Extension (..),
    ExtensionSet,
    allExtensions,
    baseExtensions,
    defaultExtensions,
    mkExtensionSet,
    isEnabled,
    extensionCode,
    readExtensionCode,
    ExtensionInfo (..),
    extensionInfo,
    extensionCatalogue,
  )
where

import Data.Set (Set)
import Data.Set qualified as Set

data Extension
  = -- | RV32I - base integer set (mandatory)
    IExt
  | -- | RV32M - integer multiply / divide
    MExt
  | -- | Zicsr - control and status register access
    ZicsrExt
  deriving (Show, Eq, Ord, Enum, Bounded)

type ExtensionSet = Set Extension

allExtensions :: ExtensionSet
allExtensions = Set.fromList extensionCatalogue

baseExtensions :: ExtensionSet
baseExtensions = Set.fromList [e | e <- extensionCatalogue, extMandatory (extensionInfo e)]

defaultExtensions :: ExtensionSet
defaultExtensions = allExtensions

mkExtensionSet :: [Extension] -> ExtensionSet
mkExtensionSet xs = Set.union baseExtensions (Set.fromList xs)

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
    extMandatory :: Bool
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
      extMandatory = True
    }
extensionInfo MExt =
  ExtensionInfo
    { extCode = "M",
      extName = "Integer Multiply / Divide",
      extSummary =
        "Hardware multiplication, division and remainder "
          ++ "(mul, mulh, mulhsu, mulhu, div, divu, rem, remu).",
      extMandatory = False
    }
extensionInfo ZicsrExt =
  ExtensionInfo
    { extCode = "Zicsr",
      extName = "Control and Status Registers",
      extSummary =
        "Atomic read/modify/write access to control and status registers "
          ++ "(csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci).",
      extMandatory = False
    }

extensionCatalogue :: [Extension]
extensionCatalogue = [minBound .. maxBound]
