module Screens.BookingOptionsScreen.ScreenData where

import Screens.Types (BookingOptionsScreenState, RidePreference)
import Services.API as API
import Data.Maybe (Maybe(..))

initData :: BookingOptionsScreenState
initData = {
  data : {
    vehicleType : "",
    vehicleNumber : "",
    vehicleName : "",
    vehicleCapacity : 0,
    downgradeOptions : [],
    ridePreferences : [],
    defaultRidePreference : defaultRidePreferenceOption
  },
  props: { 
    isBtnActive : false,
    downgraded : false,
    canSwitchToRental : false
  }
}

defaultRidePreferenceOption :: RidePreference
defaultRidePreferenceOption = {
  airConditioned : Nothing,
  driverRating : Nothing,
  isDefault : false,
  isSelected : false,
  longDescription : Nothing,
  luggageCapacity : Nothing,
  name : "",
  seatingCapacity : Nothing,
  serviceTierType : API.AUTO_RICKSHAW,
  shortDescription : Nothing,
  vehicleRating : Nothing
}
