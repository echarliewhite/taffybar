{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module System.Taffybar.ContextSpec
  ( spec
  -- * Utils
  , runTaffyDefault
  -- * Abstract Config
  , GenSimpleConfig(..)
  , toSimpleConfig
  , GenWidget(..)
  , toTaffyWidget
  , GenSpace(..)
  , GenCssPath(..)
  , toCssPaths
  , GenMonitorsAction(..)
  , toMonitorsAction
  ) where

import Control.Monad.Trans.Reader (runReaderT)
import Data.Default (def)
import Data.Ratio ((%))
import GHC.Generics (Generic)
import GI.Gtk (Widget)

import Test.Hspec hiding (context)
import Test.Hspec.QuickCheck
import Test.QuickCheck
import Test.QuickCheck.Monadic

import System.Taffybar.Context
import System.Taffybar.SimpleConfig
import System.Taffybar.Widget.SimpleClock (textClockNewWith)
import System.Taffybar.Widget.Workspaces (workspacesNew)

import System.Taffybar.Test.XvfbSpec (withXdummy, setDefaultDisplay_)

spec :: Spec
spec = sequential $ aroundAll_ (withXdummy . flip setDefaultDisplay_) $ do
  describe "Fuzz tests" $ do
    prop "eval generators" prop_genSimpleConfig
    xprop "TaffybarConfig" prop_taffybarConfig

------------------------------------------------------------------------

runTaffyDefault :: TaffyIO a -> IO a
runTaffyDefault f = buildContext def >>= runReaderT f

------------------------------------------------------------------------

-- | Represents 'SimpleTaffyConfig' in a more abstract way, so that
-- it's easier to 'show', 'shrink', 'assert', etc.
data GenSimpleConfig = GenSimpleConfig
  { monitors :: GenMonitorsAction
  , size :: StrutSize
  , padding :: GenSpace
  , position :: Position
  , spacing :: GenSpace
  , start :: [GenWidget]
  , center :: [GenWidget]
  , end :: [GenWidget]
  , css :: [GenCssPath]
  } deriving (Show, Eq, Generic)

-- | Build an actual taffy config from the abstract form.
toSimpleConfig :: GenSimpleConfig -> SimpleTaffyConfig
toSimpleConfig GenSimpleConfig{..} = SimpleTaffyConfig
  { monitorsAction = toMonitorsAction monitors
  , barHeight = size
  , barPadding = unGenSpace padding
  , barPosition = position
  , widgetSpacing = unGenSpace spacing
  , startWidgets = map toTaffyWidget start
  , centerWidgets = map toTaffyWidget center
  , endWidgets = map toTaffyWidget end
  , cssPaths = toCssPaths css
  , startupHook = pure () -- TODO: add something
  }

toTaffyWidget :: GenWidget -> TaffyIO Widget
toTaffyWidget = \case
  WorkspacesWidget -> workspacesNew def
  ClockWidget -> textClockNewWith def

toCssPaths :: [GenCssPath] -> [FilePath]
toCssPaths = map (\p -> "fixme_" ++ show p ++ ".css")

toMonitorsAction :: GenMonitorsAction -> TaffyIO [Int]
toMonitorsAction = \case
  UsePrimaryMonitor -> usePrimaryMonitor
  UseAllMonitors -> useAllMonitors
  UseTheseMonitors xs -> pure xs

instance Arbitrary GenSimpleConfig where
  arbitrary = GenSimpleConfig <$> arbitrary <*>  arbitrary <*>  arbitrary <*>  arbitrary <*>  arbitrary <*>  arbitrary <*>  arbitrary <*>  arbitrary <*>  arbitrary
  shrink = genericShrink

instance Arbitrary StrutSize where
  arbitrary = oneof
    [ ExactSize . getSmall . getPositive <$> arbitrary
    , ScreenRatio <$> elements [ 1 % 27, 1 % 50, 1 % 2 ] -- TODO: more arbitrary
    ]
  shrink (ExactSize s) = ExactSize . getPositive <$> shrink (Positive (fromIntegral s))
  shrink (ScreenRatio r) = ScreenRatio <$> shrink r

instance Arbitrary Position where
  arbitrary = arbitraryBoundedEnum
  shrink Top = []
  shrink Bottom = [Top]

newtype GenSpace = GenSpace { unGenSpace :: Int }
  deriving (Show, Read, Eq, Generic)

instance Arbitrary GenSpace where
  arbitrary = GenSpace . getSmall . getPositive <$> arbitrary
  shrink = genericShrink

data GenWidget = WorkspacesWidget | ClockWidget
  deriving (Show, Read, Eq, Ord, Bounded, Enum, Generic)

instance Arbitrary GenWidget where
  arbitrary = arbitraryBoundedEnum
  shrink = genericShrink

data GenCssPath = RedStyle | BlueStyle | MissingCss | FaultyCss
  deriving (Show, Read, Eq, Ord, Bounded, Enum, Generic)

instance Arbitrary GenCssPath where
  arbitrary = arbitraryBoundedEnum
  shrink = genericShrink

data GenMonitorsAction = UsePrimaryMonitor
                       | UseAllMonitors
                       | UseTheseMonitors [Int]
  deriving (Show, Read, Eq, Generic)

instance Arbitrary GenMonitorsAction where
  arbitrary = oneof
    [ pure UsePrimaryMonitor
    , pure UseAllMonitors
    , wild ]
    where
      -- This could be a lot meaner.
      wild = do
        NonNegative (Small n) <- arbitrary
        pure (UseTheseMonitors [0..n])
  shrink = genericShrink

------------------------------------------------------------------------

prop_genSimpleConfig :: GenSimpleConfig -> Property
prop_genSimpleConfig cfg = checkCoverage $
  cover 25 (monitors cfg == UsePrimaryMonitor) "Primary monitor only" $
  cfg === cfg

prop_taffybarConfig :: GenSimpleConfig -> Property
prop_taffybarConfig cfg = within 1_000_000 $ monadicIO $
  pure (cfg =/= cfg)
  -- Some possible assertions:
  --   startupHook executed exactly once
  --   css rules are applied
  --   css files later in list have precedence
  --   missing css => exception
  --   error in css => warning and continue
  --   widgets are visible
  --   spacing/height/position/padding are observed
  --   appears on the correct monitor
