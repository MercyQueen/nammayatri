module Screens.BookingOptionsScreen.Handler where

import Control.Monad.Except.Trans (lift)
import Control.Transformers.Back.Trans (BackT(..), FailBack(..)) as App
import Engineering.Helpers.BackTrack (getState)
import Prelude (bind, pure, ($), (<$>), discard)
import PrestoDOM.Core.Types.Language.Flow (runScreen)
import Screens.BookingOptionsScreen.Controller (ScreenOutput(..))
import Screens.BookingOptionsScreen.View as BookingOptionsScreen
import Types.App (BOOKING_OPTIONS_SCREEN_OUTPUT(..), FlowBT, GlobalState(..), ScreenType(..))
import Types.ModifyScreenState (modifyScreenState)

bookingOptions :: FlowBT String BOOKING_OPTIONS_SCREEN_OUTPUT
bookingOptions = do
  (GlobalState state) <- getState
  action <- lift $ lift $ runScreen $ BookingOptionsScreen.screen state.bookingOptionsScreen
  case action of
    ChangeRidePreference updatedState service -> do
      modifyScreenState $ BookingOptionsScreenType (\_ -> updatedState)
      App.BackT $ App.NoBack <$> (pure $ CHANGE_RIDE_PREFERENCE updatedState service)
    GoBack -> App.BackT $ pure App.GoBack
