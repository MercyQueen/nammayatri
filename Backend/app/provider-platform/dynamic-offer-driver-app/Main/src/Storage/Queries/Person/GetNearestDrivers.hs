module Storage.Queries.Person.GetNearestDrivers (getNearestDrivers, NearestDriversResult (..)) where

import qualified Data.HashMap.Strict as HashMap
import qualified Data.List as List
import Domain.Types.DriverInformation as DriverInfo
import Domain.Types.Merchant
import Domain.Types.Person as Person
import Domain.Types.ServiceTierType as DVST
import Domain.Types.Vehicle as DV
import Domain.Types.VehicleServiceTier as DVST
import Kernel.External.Maps as Maps
import qualified Kernel.External.Notification.FCM.Types as FCM
import Kernel.Prelude
import Kernel.Tools.Metrics.CoreMetrics (CoreMetrics)
import Kernel.Types.Id
import Kernel.Utils.CalculateDistance (distanceBetweenInMeters)
import Kernel.Utils.Common hiding (Value)
import qualified SharedLogic.External.LocationTrackingService.Types as LT
import qualified Storage.Queries.DriverInformation.Internal as Int
import qualified Storage.Queries.DriverLocation.Internal as Int
import qualified Storage.Queries.Person.Internal as Int
import qualified Storage.Queries.Vehicle.Internal as Int

data NearestDriversResult = NearestDriversResult
  { driverId :: Id Driver,
    driverDeviceToken :: Maybe FCM.FCMRecipientToken,
    language :: Maybe Maps.Language,
    onRide :: Bool,
    distanceToDriver :: Meters,
    variant :: DV.Variant,
    serviceTier :: DVST.ServiceTierType,
    airConditioned :: Maybe Double,
    lat :: Double,
    lon :: Double,
    mode :: Maybe DriverInfo.DriverMode
  }
  deriving (Generic, Show, HasCoordinates)

getNearestDrivers ::
  (MonadFlow m, MonadTime m, LT.HasLocationService m r, CoreMetrics m, EsqDBFlow m r, CacheFlow m r) =>
  [DVST.VehicleServiceTier] ->
  Maybe ServiceTierType ->
  LatLong ->
  Meters ->
  Id Merchant ->
  Bool ->
  Maybe Seconds ->
  Bool ->
  m [NearestDriversResult]
getNearestDrivers cityServiceTiers mbServiceTier fromLocLatLong radiusMeters merchantId onlyNotOnRide mbDriverPositionInfoExpiry isRental = do
  driverLocs <- Int.getDriverLocsWithCond merchantId mbDriverPositionInfoExpiry fromLocLatLong radiusMeters
  driverInfos <- Int.getDriverInfosWithCond (driverLocs <&> (.driverId)) onlyNotOnRide (not onlyNotOnRide) isRental
  vehicle <- Int.getVehicles driverInfos
  drivers <- Int.getDrivers vehicle
  logDebug $ "GetNearestDriver - DLoc:- " <> show (length driverLocs) <> " DInfo:- " <> show (length driverInfos) <> " Vehicles:- " <> show (length vehicle) <> " Drivers:- " <> show (length drivers)
  let res = linkArrayList driverLocs driverInfos vehicle drivers
  logDebug $ "GetNearestDrivers Result:- " <> show (length res)
  return res
  where
    linkArrayList driverLocations driverInformations vehicles persons =
      let personHashMap = HashMap.fromList $ (\p -> (p.id, p)) <$> persons
          driverInfoHashMap = HashMap.fromList $ (\info -> (info.driverId, info)) <$> driverInformations
          vehicleHashMap = HashMap.fromList $ (\v -> (v.driverId, v)) <$> vehicles
       in concat $ mapMaybe (buildFullDriverList personHashMap vehicleHashMap driverInfoHashMap) driverLocations

    buildFullDriverList personHashMap vehicleHashMap driverInfoHashMap location = do
      let driverId' = location.driverId
      person <- HashMap.lookup driverId' personHashMap
      vehicle <- HashMap.lookup driverId' vehicleHashMap
      info <- HashMap.lookup driverId' driverInfoHashMap
      let dist = (realToFrac $ distanceBetweenInMeters fromLocLatLong $ LatLong {lat = location.lat, lon = location.lon}) :: Double
      -- ideally should be there inside the vehicle.selectedServiceTiers but still to make sure we have a default service tier for the driver
      let cityServiceTiersHashMap = HashMap.fromList $ (\vst -> (vst.serviceTierType, vst)) <$> cityServiceTiers
      let defaultServiceTierForDriver = (.serviceTierType) <$> (find (\vst -> vehicle.variant `elem` vst.defaultForVehicleVariant) cityServiceTiers)
      let selectedDriverServiceTiers =
            case defaultServiceTierForDriver of
              Just defaultServiceTierForDriver' ->
                if defaultServiceTierForDriver' `elem` vehicle.selectedServiceTiers
                  then vehicle.selectedServiceTiers
                  else [defaultServiceTierForDriver'] <> vehicle.selectedServiceTiers
              Nothing -> vehicle.selectedServiceTiers
      case mbServiceTier of
        Just serviceTier ->
          if serviceTier `elem` selectedDriverServiceTiers
            then List.singleton <$> mkDriverResult person vehicle info dist cityServiceTiersHashMap serviceTier
            else Nothing
        Nothing -> Just (mapMaybe (mkDriverResult person vehicle info dist cityServiceTiersHashMap) selectedDriverServiceTiers)
      where
        mkDriverResult person vehicle info dist cityServiceTiersHashMap serviceTier = do
          serviceTierInfo <- HashMap.lookup serviceTier cityServiceTiersHashMap
          Just $ NearestDriversResult (cast person.id) person.deviceToken person.language info.onRide (roundToIntegral dist) vehicle.variant serviceTier serviceTierInfo.airConditioned location.lat location.lon info.mode
