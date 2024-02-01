{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}
{-# LANGUAGE OverloadedLabels #-}

module Beckn.OnDemand.Utils.Common where

import qualified Beckn.Types.Core.Taxi.OnSearch as OS
import qualified BecknV2.OnDemand.Types as Spec
import Control.Lens
import Data.Aeson
import qualified Data.Aeson as A
import qualified Data.List as List
import Data.Maybe
import qualified Data.Text as T
import qualified Domain.Types.Booking as DBooking
import qualified Domain.Types.Common as DCT
import qualified Domain.Types.Location as DL
import qualified Domain.Types.Location as DLoc
import qualified Domain.Types.Merchant.MerchantPaymentMethod as DMPM
import qualified Domain.Types.Person as SP
import qualified Domain.Types.Ride as DRide
import qualified Domain.Types.Vehicle as DVeh
import qualified Domain.Types.Vehicle.Variant as Variant
import EulerHS.Prelude hiding (id, state, view, (%~), (^?))
import Kernel.External.Maps as Maps
import qualified Kernel.Types.Beckn.Context as Context
import qualified Kernel.Types.Beckn.Gps as Gps
import Kernel.Types.Common
import Kernel.Utils.Common
import Tools.Error

firstStop :: [Spec.Stop] -> Maybe Spec.Stop
firstStop = find (\stop -> Spec.stopType stop == Just "START")

lastStop :: [Spec.Stop] -> Maybe Spec.Stop
lastStop = find (\stop -> Spec.stopType stop == Just "END")

mkStops :: LatLong -> Maybe LatLong -> Maybe [Spec.Stop]
mkStops origin mbDestination = do
  let originGps = Gps.Gps {lat = origin.lat, lon = origin.lon}
      destinationGps destination = Gps.Gps {lat = destination.lat, lon = destination.lon}
  Just $
    catMaybes
      [ Just $
          Spec.Stop
            { stopLocation =
                Just $
                  Spec.Location
                    { locationAddress = Nothing, -- For start and end in on_search, we send address as nothing
                      locationAreaCode = Nothing,
                      locationCity = Nothing,
                      locationCountry = Nothing,
                      locationGps = A.decode $ A.encode originGps,
                      locationState = Nothing,
                      locationId = Nothing
                    },
              stopType = Just "START",
              stopAuthorization = Nothing,
              stopTime = Nothing
            },
        ( \destination ->
            Spec.Stop
              { stopLocation =
                  Just $
                    Spec.Location
                      { locationAddress = Nothing, -- JAYPAL, Confirm if it is correct to put it here
                        locationAreaCode = Nothing,
                        locationCity = Nothing,
                        locationCountry = Nothing,
                        locationGps = A.decode $ A.encode $ destinationGps destination,
                        locationState = Nothing,
                        locationId = Nothing
                      },
                stopType = Just "END",
                stopAuthorization = Nothing,
                stopTime = Nothing
              }
        )
          <$> mbDestination
      ]

parseLatLong :: Text -> LatLong
parseLatLong a =
  case T.splitOn "," a of
    [latStr, longStr] ->
      let lat = fromMaybe 0.0 $ readMaybe $ T.unpack latStr
          lon = fromMaybe 0.0 $ readMaybe $ T.unpack longStr
       in LatLong lat lon
    _ -> error "Unable to parse LatLong"

getTransactionId :: MonadFlow m => Spec.Context -> m Text
getTransactionId context = do
  transactionUuid <- context.contextTransactionId & fromMaybeM (InvalidRequest "Missing transaction_id")
  pure $ T.pack $ show transactionUuid

getMessageId :: MonadFlow m => Spec.Context -> m Text
getMessageId context = do
  messageUuid <- context.contextMessageId & fromMaybeM (InvalidRequest "Missing message_id")
  pure $ T.pack $ show messageUuid

getContextCity :: MonadFlow m => Spec.Context -> m Context.City
getContextCity context = do
  location <- context.contextLocation & fromMaybeM (InvalidRequest "Missing contextLocation")
  city <- location.locationCity & fromMaybeM (InvalidRequest "Missing locationCity")
  cityText <- city.cityCode & fromMaybeM (InvalidRequest "Missing cityCode")
  decode (encode cityText) & fromMaybeM (InvalidRequest $ "Error in parsing cityCode: " <> cityText)

getContextCountry :: MonadFlow m => Spec.Context -> m Context.Country
getContextCountry context = do
  location <- context.contextLocation & fromMaybeM (InvalidRequest "Missing contextLocation")
  country <- location.locationCountry & fromMaybeM (InvalidRequest "Missing locationCountry")
  countryCodeText <- country.countryCode & fromMaybeM (InvalidRequest "Missing countryCode")
  decode (encode countryCodeText) & fromMaybeM (InvalidRequest $ "Error in parsing countryCode: " <> countryCodeText)

getContextBapUri :: MonadFlow m => Spec.Context -> m BaseUrl
getContextBapUri context = do
  bapUriText <- context.contextBapUri & fromMaybeM (InvalidRequest "Missing contextBapUri")
  decode (encode bapUriText) & fromMaybeM (InvalidRequest $ "Error in parsing contextBapUri: " <> bapUriText)

getContextBppUri :: MonadFlow m => Spec.Context -> m (Maybe BaseUrl)
getContextBppUri context = do
  let mbBppUriText = context.contextBppUri
  case mbBppUriText of
    Nothing -> pure Nothing
    Just bppUriText -> Just <$> A.decode (A.encode bppUriText) & fromMaybeM (InvalidRequest $ "Error in parsing contextBppUri: " <> bppUriText)

withTransactionIdLogTag :: (Log m) => Text -> m a -> m a
withTransactionIdLogTag = withTransactionIdLogTag'

getContextBapId :: MonadFlow m => Spec.Context -> m Text
getContextBapId context = do
  context.contextBapId & fromMaybeM (InvalidRequest "Missing contextBapId")

mkBppUri ::
  ( HasFlowEnv m r '["nwAddress" ::: BaseUrl]
  ) =>
  Text ->
  m BaseUrl
mkBppUri merchantId =
  asks (.nwAddress)
    <&> #baseUrlPath %~ (<> "/" <> T.unpack merchantId)

castVariant :: Variant.Variant -> (Text, Text)
castVariant Variant.SEDAN = ("CAB", "SEDAN")
castVariant Variant.HATCHBACK = ("CAB", "HATCHBACK")
castVariant Variant.SUV = ("CAB", "SUV")
castVariant Variant.AUTO_RICKSHAW = ("AUTO_RICKSHAW", "AUTO_RICKSHAW")
castVariant Variant.TAXI = ("CAB", "TAXI")
castVariant Variant.TAXI_PLUS = ("CAB", "TAXI_PLUS")

mkFulfillmentType :: DCT.TripCategory -> Text
mkFulfillmentType = \case
  DCT.OneWay DCT.OneWayRideOtp -> "RIDE_OTP"
  DCT.RoundTrip DCT.RideOtp -> "RIDE_OTP"
  DCT.RideShare DCT.RideOtp -> "RIDE_OTP"
  DCT.Rental _ -> "RENTAL"
  _ -> "RIDE"

rationaliseMoney :: Money -> Text
rationaliseMoney = OS.valueToString . OS.DecimalValue . toRational

castDPaymentType :: DMPM.PaymentType -> Text
castDPaymentType DMPM.PREPAID = "ON_ORDER" -- TODO::Beckn, not there in spec.
castDPaymentType DMPM.POSTPAID = "ON_FULFILLMENT"

parseVehicleVariant :: Maybe Text -> Maybe Text -> Maybe Variant.Variant
parseVehicleVariant mbCategory mbVariant = case (mbCategory, mbVariant) of
  (Just "CAB", Just "SEDAN") -> Just Variant.SEDAN
  (Just "CAB", Just "SUV") -> Just Variant.SUV
  (Just "CAB", Just "HATCHBACK") -> Just Variant.HATCHBACK
  (Just "AUTO_RICKSHAW", Just "AUTO_RICKSHAW") -> Just Variant.AUTO_RICKSHAW
  (Just "CAB", Just "TAXI") -> Just Variant.TAXI
  (Just "CAB", Just "TAXI_PLUS") -> Just Variant.TAXI_PLUS
  _ -> Nothing

parseAddress :: Spec.Location -> Maybe DL.LocationAddress
parseAddress Spec.Location {..} = do
  let areaCode = locationAreaCode
  let city = locationCity >>= (.cityName)
  let state = locationState >>= (.stateName)
  let country = locationCountry >>= (.countryName)
  let fullAddress = mkFullAddress city state country
  Just $
    DL.LocationAddress
      { street = Nothing,
        door = Nothing,
        building = Nothing,
        area = Nothing, -- TODO: Fetch this, discuss with ONDC
        ..
      }
  where
    mkFullAddress city state country = do
      let strictFields = catMaybes $ filter (not . isEmpty) [locationAddress, city, state, country]
      if null strictFields
        then Nothing
        else Just $ T.intercalate ", " strictFields

    isEmpty :: Maybe Text -> Bool
    isEmpty = maybe True (T.null . T.replace " " "")

mkStops' :: DLoc.Location -> Maybe DLoc.Location -> Maybe Text -> Maybe [Spec.Stop]
mkStops' origin mbDestination mAuthorization =
  let originGps = Gps.Gps {lat = origin.lat, lon = origin.lon}
      destinationGps dest = Gps.Gps {lat = dest.lat, lon = dest.lon}
   in Just $
        catMaybes
          [ Just $
              Spec.Stop
                { stopLocation =
                    Just $
                      Spec.Location
                        { locationAddress = Just $ mkAddress origin.address,
                          locationAreaCode = origin.address.areaCode,
                          locationCity = Just $ Spec.City Nothing origin.address.city,
                          locationCountry = Just $ Spec.Country Nothing origin.address.country,
                          locationGps = A.decode $ A.encode originGps,
                          locationState = Just $ Spec.State origin.address.state,
                          locationId = Nothing
                        },
                  stopType = Just "START",
                  stopAuthorization = mAuthorization >>= mkAuthorization,
                  stopTime = Nothing
                },
            ( \destination ->
                Spec.Stop
                  { stopLocation =
                      Just $
                        Spec.Location
                          { locationAddress = Just $ mkAddress destination.address,
                            locationAreaCode = destination.address.areaCode,
                            locationCity = Just $ Spec.City Nothing destination.address.city,
                            locationCountry = Just $ Spec.Country Nothing destination.address.country,
                            locationGps = A.decode $ A.encode $ destinationGps destination,
                            locationState = Just $ Spec.State destination.address.state,
                            locationId = Nothing
                          },
                    stopType = Just "END",
                    stopAuthorization = Nothing,
                    stopTime = Nothing
                  }
            )
              <$> mbDestination
          ]
  where
    mkAddress :: DLoc.LocationAddress -> Text
    mkAddress DLoc.LocationAddress {..} = T.intercalate ", " $ catMaybes [door, building, street]

    mkAuthorization :: Text -> Maybe Spec.Authorization
    mkAuthorization auth =
      Just $
        Spec.Authorization
          { authorizationToken = Just auth,
            authorizationType = Just "OTP"
          }

data DriverInfo = DriverInfo
  { mobileNumber :: Text,
    name :: Text,
    tags :: Maybe [Spec.TagGroup]
  }

showVariant :: DVeh.Variant -> Maybe Text
showVariant = A.decode . A.encode

-- common for on_update & on_status
mkStopsOUS :: DBooking.Booking -> DRide.Ride -> Text -> Maybe [Spec.Stop]
mkStopsOUS booking ride rideOtp =
  let origin = booking.fromLocation
      mbDestination = booking.toLocation
      originGps = Gps.Gps {lat = origin.lat, lon = origin.lon}
      destinationGps dest = Gps.Gps {lat = dest.lat, lon = dest.lon}
   in Just $
        catMaybes
          [ Just $
              Spec.Stop
                { stopLocation =
                    Just $
                      Spec.Location
                        { locationAddress = Just $ mkAddress origin.address,
                          locationAreaCode = origin.address.areaCode,
                          locationCity = Just $ Spec.City Nothing origin.address.city,
                          locationCountry = Just $ Spec.Country Nothing origin.address.country,
                          locationGps = A.decode $ A.encode originGps,
                          locationState = Just $ Spec.State origin.address.state,
                          locationId = Nothing
                        },
                  stopType = Just "START",
                  stopAuthorization =
                    Just $
                      Spec.Authorization
                        { authorizationToken = Just rideOtp,
                          authorizationType = Just "OTP"
                        },
                  stopTime = Just $ Spec.Time {timeTimestamp = ride.tripStartTime}
                },
            ( \destination ->
                Spec.Stop
                  { stopLocation =
                      Just $
                        Spec.Location
                          { locationAddress = Just $ mkAddress destination.address,
                            locationAreaCode = destination.address.areaCode,
                            locationCity = Just $ Spec.City Nothing destination.address.city,
                            locationCountry = Just $ Spec.Country Nothing destination.address.country,
                            locationGps = A.decode $ A.encode $ destinationGps destination,
                            locationState = Just $ Spec.State destination.address.state,
                            locationId = Nothing
                          },
                    stopType = Just "END",
                    stopAuthorization = Nothing,
                    stopTime = Just $ Spec.Time {timeTimestamp = ride.tripEndTime}
                  }
            )
              <$> mbDestination
          ]
  where
    mkAddress :: DLoc.LocationAddress -> Text
    mkAddress DLoc.LocationAddress {..} = T.intercalate ", " $ catMaybes [door, building, street]

-- common for on_update & on_status
mkFulfillmentV2 ::
  (MonadFlow m, EncFlow m r) =>
  Maybe SP.Person ->
  DRide.Ride ->
  DBooking.Booking ->
  Maybe DVeh.Vehicle ->
  Maybe Text ->
  Maybe [Spec.TagGroup] ->
  Maybe [Spec.TagGroup] ->
  Bool ->
  Bool ->
  Maybe Text ->
  m Spec.Fulfillment
mkFulfillmentV2 mbDriver ride booking mbVehicle mbImage mbTags mbPersonTags isDriverBirthDay isFreeRide mbEvent = do
  mbDInfo <- driverInfo
  let rideOtp = case ride.status of
        DRide.INPROGRESS -> fromMaybe ride.otp ride.endOtp
        _ -> ride.otp
  pure $
    Spec.Fulfillment
      { fulfillmentId = Just ride.id.getId,
        fulfillmentStops = mkStopsOUS booking ride rideOtp,
        fulfillmentType = Just $ mkFulfillmentType booking.tripCategory,
        fulfillmentAgent =
          Just $
            Spec.Agent
              { agentContact =
                  mbDInfo >>= \dInfo ->
                    Just $
                      Spec.Contact
                        { contactPhone = Just dInfo.mobileNumber
                        },
                agentPerson =
                  Just $
                    Spec.Person
                      { personId = Nothing,
                        personImage =
                          Just $
                            Spec.Image
                              { imageHeight = Nothing,
                                imageSizeType = Nothing,
                                imageUrl = mbImage,
                                imageWidth = Nothing
                              },
                        personName = mbDInfo >>= Just . (.name),
                        personTags = mbDInfo >>= (.tags) & (mbPersonTags <>)
                      }
              },
        fulfillmentVehicle =
          mbVehicle >>= \vehicle -> do
            let (category, variant) = castVariant vehicle.variant
            Just $
              Spec.Vehicle
                { vehicleColor = Just vehicle.color,
                  vehicleModel = Just vehicle.model,
                  vehicleRegistration = Just vehicle.registrationNo,
                  vehicleCategory = Just category,
                  vehicleVariant = Just variant,
                  vehicleMake = Nothing
                },
        fulfillmentCustomer = Nothing,
        fulfillmentState =
          mbEvent
            >> ( Just $
                   Spec.FulfillmentState
                     { fulfillmentStateDescriptor =
                         Just $
                           Spec.Descriptor
                             { descriptorCode = mbEvent,
                               descriptorName = Nothing,
                               descriptorShortDesc = Nothing
                             }
                     }
               ),
        fulfillmentTags = mbTags
      }
  where
    driverInfo = forM mbDriver $ \driver -> do
      dPhoneNum <- SP.getPersonNumber driver >>= fromMaybeM (InternalError "Driver mobile number is not present in OnUpdateBuildReq.")
      dName <- SP.getPersonFullName driver & fromMaybeM (PersonFieldNotPresent "firstName")
      let dTags = mkDriverDetailsTags driver isDriverBirthDay isFreeRide
      pure $
        DriverInfo
          { mobileNumber = dPhoneNum,
            name = dName,
            tags = dTags
          }

mkDriverDetailsTags :: SP.Person -> Bool -> Bool -> Maybe [Spec.TagGroup]
mkDriverDetailsTags driver isDriverBirthDay isFreeRide =
  Just
    [ Spec.TagGroup
        { tagGroupDescriptor =
            Just $
              Spec.Descriptor
                { descriptorCode = Just "driver_details",
                  descriptorName = Just "Driver Details",
                  descriptorShortDesc = Nothing
                },
          tagGroupDisplay = Just False,
          tagGroupList =
            Just $
              registeredAtSingleton
                ++ driverRatingSingleton
                ++ isDriverBirthDaySingleton
                ++ isFreeRideSingleton
        }
    ]
  where
    registeredAtSingleton =
      List.singleton $
        Spec.Tag
          { tagDescriptor =
              Just $
                Spec.Descriptor
                  { descriptorCode = Just "registered_at",
                    descriptorName = Just "Registered At",
                    descriptorShortDesc = Nothing
                  },
            tagDisplay = Just False,
            tagValue = Just $ show driver.createdAt
          }

    driverRatingSingleton
      | isNothing driver.rating = []
      | otherwise =
        List.singleton $
          Spec.Tag
            { tagDescriptor =
                Just $
                  Spec.Descriptor
                    { descriptorCode = Just "rating",
                      descriptorName = Just "rating",
                      descriptorShortDesc = Nothing
                    },
              tagDisplay = Just False,
              tagValue = show <$> driver.rating
            }

    isDriverBirthDaySingleton
      | not isDriverBirthDay = []
      | otherwise =
        List.singleton $
          Spec.Tag
            { tagDescriptor =
                Just $
                  Spec.Descriptor
                    { descriptorCode = Just "is_driver_birthday",
                      descriptorName = Just "Is Driver BirthDay",
                      descriptorShortDesc = Nothing
                    },
              tagDisplay = Just False,
              tagValue = Just $ show isDriverBirthDay
            }

    isFreeRideSingleton
      | not isFreeRide = []
      | otherwise =
        List.singleton $
          Spec.Tag
            { tagDescriptor =
                Just $
                  Spec.Descriptor
                    { descriptorCode = Just "is_free_ride",
                      descriptorName = Just "Is Free Ride",
                      descriptorShortDesc = Nothing
                    },
              tagDisplay = Just False,
              tagValue = Just $ show isFreeRide
            }

mkLocationTagGroupV2 :: Maybe Maps.LatLong -> [Spec.TagGroup]
mkLocationTagGroupV2 location =
  [ Spec.TagGroup
      { tagGroupDisplay = Just False,
        tagGroupDescriptor =
          Just $
            Spec.Descriptor
              { descriptorCode = Just "current_location",
                descriptorName = Just "Current Location",
                descriptorShortDesc = Nothing
              },
        tagGroupList =
          Just
            [ Spec.Tag
                { tagDisplay = Just False,
                  tagDescriptor =
                    Just $
                      Spec.Descriptor
                        { descriptorCode = Just "current_location_lat",
                          descriptorName = Just "Current Location Lat",
                          descriptorShortDesc = Nothing
                        },
                  tagValue = Just . show . (.lat) =<< location
                },
              Spec.Tag
                { tagDisplay = Just False,
                  tagDescriptor =
                    Just $
                      Spec.Descriptor
                        { descriptorCode = Just "current_location_lon",
                          descriptorName = Just "Current Location Lon",
                          descriptorShortDesc = Nothing
                        },
                  tagValue = Just . show . (.lon) =<< location
                }
            ]
      }
  ]

mkArrivalTimeTagGroupV2 :: Maybe UTCTime -> [Spec.TagGroup]
mkArrivalTimeTagGroupV2 arrivalTime =
  [ Spec.TagGroup
      { tagGroupDisplay = Just False,
        tagGroupDescriptor =
          Just $
            Spec.Descriptor
              { descriptorCode = Just "driver_arrived_info",
                descriptorName = Just "Driver Arrived Info",
                descriptorShortDesc = Nothing
              },
        tagGroupList =
          Just
            [ Spec.Tag
                { tagDisplay = Just False,
                  tagDescriptor =
                    Just $
                      Spec.Descriptor
                        { descriptorCode = Just "arrival_time",
                          descriptorName = Just "Chargeable Distance",
                          descriptorShortDesc = Nothing
                        },
                  tagValue = show <$> arrivalTime
                }
            ]
      }
  ]