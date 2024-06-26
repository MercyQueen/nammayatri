{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}
{-# LANGUAGE ApplicativeDo #-}

module Domain.Action.UI.DriverOnboarding.DriverLicense
  ( DriverDLReq (..),
    DriverDLRes,
    verifyDL,
    onVerifyDL,
    convertUTCTimetoDate,
  )
where

import qualified AWS.S3 as S3
import Control.Applicative ((<|>))
import qualified Data.Text as T
import Data.Time (nominalDay)
import Domain.Types.DocumentVerificationConfig (DocumentVerificationConfig)
import qualified Domain.Types.DocumentVerificationConfig as DTO
import qualified Domain.Types.DriverLicense as Domain
import qualified Domain.Types.IdfyVerification as Domain
import qualified Domain.Types.Image as Image
import qualified Domain.Types.Merchant as DM
import qualified Domain.Types.Merchant.MerchantOperatingCity as DMOC
import qualified Domain.Types.Person as Person
import Domain.Types.Vehicle
import Environment
import Kernel.External.Encryption
import qualified Kernel.External.Verification.Interface.Idfy as Idfy
import Kernel.Prelude
import qualified Kernel.Storage.Hedis as Redis
import Kernel.Types.APISuccess
import Kernel.Types.Error
import Kernel.Types.Id
import Kernel.Types.Predicate
import Kernel.Types.Validation
import Kernel.Utils.Common
import Kernel.Utils.Validation
import SharedLogic.DriverOnboarding
import qualified Storage.CachedQueries.DocumentVerificationConfig as QODC
import qualified Storage.CachedQueries.Merchant.TransporterConfig as QTC
import qualified Storage.Queries.DriverInformation as DriverInfo
import qualified Storage.Queries.DriverLicense as Query
import qualified Storage.Queries.IdfyVerification as IVQuery
import qualified Storage.Queries.Image as ImageQuery
import qualified Storage.Queries.Person as Person
import Tools.Error
import qualified Tools.Verification as Verification

data DriverDLReq = DriverDLReq
  { driverLicenseNumber :: Text,
    operatingCity :: Text,
    driverDateOfBirth :: UTCTime,
    vehicleCategory :: Maybe Category,
    imageId1 :: Id Image.Image,
    imageId2 :: Maybe (Id Image.Image),
    dateOfIssue :: Maybe UTCTime
  }
  deriving (Generic, ToSchema, ToJSON, FromJSON)

type DriverDLRes = APISuccess

validateDriverDLReq :: UTCTime -> Validate DriverDLReq
validateDriverDLReq now DriverDLReq {..} =
  sequenceA_
    [ validateField "driverLicenseNumber" driverLicenseNumber licenseNum,
      validateField "driverDateOfBirth" driverDateOfBirth $ InRange @UTCTime t60YearsAgo t18YearsAgo
    ]
  where
    licenseNum = LengthInRange 5 20
    t18YearsAgo = yearsAgo 18
    t60YearsAgo = yearsAgo 80
    yearsAgo i = negate (nominalDay * 365 * i) `addUTCTime` now

verifyDL ::
  Bool ->
  Maybe DM.Merchant ->
  (Id Person.Person, Id DM.Merchant, Id DMOC.MerchantOperatingCity) ->
  DriverDLReq ->
  Flow DriverDLRes
verifyDL isDashboard mbMerchant (personId, _, merchantOpCityId) req@DriverDLReq {..} = do
  now <- getCurrentTime
  runRequestValidation (validateDriverDLReq now) req
  person <- Person.findById personId >>= fromMaybeM (PersonNotFound personId.getId)
  driverInfo <- DriverInfo.findById (cast personId) >>= fromMaybeM (PersonNotFound personId.getId)
  when driverInfo.blocked $ throwError DriverAccountBlocked
  whenJust mbMerchant $ \merchant -> do
    unless (merchant.id == person.merchantId) $ throwError (PersonNotFound personId.getId)
  transporterConfig <- QTC.findByMerchantOpCityId merchantOpCityId (Just driverInfo.driverId.getId) (Just "driverId") >>= fromMaybeM (TransporterConfigNotFound merchantOpCityId.getId)
  documentVerificationConfig <- QODC.findByMerchantOpCityIdAndDocumentTypeAndCategory merchantOpCityId DTO.DriverLicense (fromMaybe CAR req.vehicleCategory) >>= fromMaybeM (DocumentVerificationConfigNotFound merchantOpCityId.getId (show DTO.DriverLicense))
  nameOnCard <-
    if (isNothing dateOfIssue && documentVerificationConfig.checkExtraction && (not isDashboard || transporterConfig.checkImageExtractionForDashboard))
      then do
        image1 <- getImage imageId1
        image2 <- getImage `mapM` imageId2
        resp <-
          Verification.extractDLImage person.merchantId merchantOpCityId $
            Verification.ExtractImageReq {image1, image2, driverId = person.id.getId}
        case resp.extractedDL of
          Just extractedDL -> do
            let extractDLNumber = removeSpaceAndDash <$> extractedDL.dlNumber
            let dlNumber = removeSpaceAndDash <$> Just driverLicenseNumber
            let nameOnCard = extractedDL.nameOnCard
            -- disable this check for debugging with mock-idfy
            cacheExtractedDl person.id extractDLNumber operatingCity
            unless (extractDLNumber == dlNumber) $
              throwImageError imageId1 $ ImageDocumentNumberMismatch (maybe "null" maskText extractDLNumber) (maybe "null" maskText dlNumber)
            return nameOnCard
          Nothing -> throwImageError imageId1 ImageExtractionFailed
      else return Nothing
  mdriverLicense <- Query.findByDLNumber driverLicenseNumber

  case mdriverLicense of
    Just driverLicense -> do
      unless (driverLicense.driverId == personId) $ throwImageError imageId1 DLAlreadyLinked
      unless (driverLicense.licenseExpiry > now) $ throwImageError imageId1 DLAlreadyUpdated
      when (driverLicense.verificationStatus == Domain.INVALID) $ throwError DLInvalid
      when (driverLicense.verificationStatus == Domain.VALID) $ throwError DLAlreadyUpdated
      verifyDLFlow person merchantOpCityId documentVerificationConfig driverLicenseNumber driverDateOfBirth imageId1 imageId2 dateOfIssue nameOnCard req.vehicleCategory
    Nothing -> do
      mDriverDL <- Query.findByDriverId personId
      when (isJust mDriverDL) $ throwImageError imageId1 DriverAlreadyLinked
      verifyDLFlow person merchantOpCityId documentVerificationConfig driverLicenseNumber driverDateOfBirth imageId1 imageId2 dateOfIssue nameOnCard req.vehicleCategory
  return Success
  where
    getImage :: Id Image.Image -> Flow Text
    getImage imageId = do
      imageMetadata <- ImageQuery.findById imageId >>= fromMaybeM (ImageNotFound imageId.getId)
      unless (imageMetadata.isValid) $ throwError (ImageNotValid imageId.getId)
      unless (imageMetadata.personId == personId) $ throwError (ImageNotFound imageId.getId)
      unless (imageMetadata.imageType == DTO.DriverLicense) $
        throwError (ImageInvalidType (show DTO.DriverLicense) (show imageMetadata.imageType))
      S3.get $ T.unpack imageMetadata.s3Path

verifyDLFlow :: Person.Person -> Id DMOC.MerchantOperatingCity -> DocumentVerificationConfig -> Text -> UTCTime -> Id Image.Image -> Maybe (Id Image.Image) -> Maybe UTCTime -> Maybe Text -> Maybe Category -> Flow ()
verifyDLFlow person merchantOpCityId documentVerificationConfig dlNumber driverDateOfBirth imageId1 imageId2 dateOfIssue nameOnCard mbVehicleCategory = do
  now <- getCurrentTime
  let imageExtractionValidation =
        if isNothing dateOfIssue && documentVerificationConfig.checkExtraction
          then Domain.Success
          else Domain.Skipped
  verifyRes <-
    Verification.verifyDLAsync person.merchantId merchantOpCityId $
      Verification.VerifyDLAsyncReq {dlNumber, dateOfBirth = driverDateOfBirth, driverId = person.id.getId}
  encryptedDL <- encrypt dlNumber
  idfyVerificationEntity <- mkIdfyVerificationEntity verifyRes.requestId now imageExtractionValidation encryptedDL
  IVQuery.create idfyVerificationEntity
  where
    mkIdfyVerificationEntity requestId now imageExtractionValidation encryptedDL = do
      id <- generateGUID
      return $
        Domain.IdfyVerification
          { id,
            driverId = person.id,
            documentImageId1 = imageId1,
            documentImageId2 = imageId2,
            requestId,
            imageExtractionValidation = imageExtractionValidation,
            documentNumber = encryptedDL,
            issueDateOnDoc = dateOfIssue,
            driverDateOfBirth = Just driverDateOfBirth,
            docType = DTO.DriverLicense,
            status = "pending",
            idfyResponse = Nothing,
            multipleRC = Nothing,
            retryCount = Just 0,
            nameOnCard,
            vehicleCategory = mbVehicleCategory,
            merchantId = Just person.merchantId,
            merchantOperatingCityId = Just merchantOpCityId,
            createdAt = now,
            updatedAt = now
          }

onVerifyDL :: Domain.IdfyVerification -> Idfy.DLVerificationOutput -> Flow AckResponse
onVerifyDL verificationReq output = do
  person <- Person.findById verificationReq.driverId >>= fromMaybeM (PersonNotFound verificationReq.driverId.getId)
  let key = dlCacheKey person.id
  extractedDlAndOperatingCity <- Redis.safeGet key
  void $ Redis.del key
  case (output.status, verificationReq.issueDateOnDoc, extractedDlAndOperatingCity, verificationReq.driverDateOfBirth) of
    (Just status, Just issueDate, Just (extractedDL, operatingCity), Just dob) | status == "id_not_found" -> dlNotFoundFallback issueDate (extractedDL, operatingCity) dob verificationReq person
    _ -> linkDl person
  where
    linkDl :: Person.Person -> Flow AckResponse
    linkDl person = do
      if verificationReq.imageExtractionValidation == Domain.Skipped
        && isJust verificationReq.issueDateOnDoc
        && ( (convertUTCTimetoDate <$> verificationReq.issueDateOnDoc)
               /= (convertUTCTimetoDate <$> (convertTextToUTC output.date_of_issue))
           )
        then do
          _ <- IVQuery.updateExtractValidationStatus Domain.Failed verificationReq.requestId
          pure Ack
        else do
          now <- getCurrentTime
          id <- generateGUID
          documentVerificationConfig <- QODC.findByMerchantOpCityIdAndDocumentTypeAndCategory person.merchantOperatingCityId DTO.DriverLicense (fromMaybe CAR verificationReq.vehicleCategory) >>= fromMaybeM (DocumentVerificationConfigNotFound person.merchantOperatingCityId.getId (show DTO.DriverLicense))
          mEncryptedDL <- encrypt `mapM` output.id_number
          let mLicenseExpiry = convertTextToUTC (output.t_validity_to <|> output.nt_validity_to)
          let mDriverLicense = createDL person.merchantId documentVerificationConfig person.id output id verificationReq.documentImageId1 verificationReq.documentImageId2 verificationReq.nameOnCard now <$> mEncryptedDL <*> mLicenseExpiry

          case mDriverLicense of
            Just driverLicense -> do
              Query.upsert driverLicense
              case driverLicense.driverName of
                Just name_ -> void $ Person.updateName person.id name_
                Nothing -> pure ()
              return Ack
            Nothing -> return Ack

dlCacheKey :: Id Person.Person -> Text
dlCacheKey personId =
  "providerPlatform:dlCacheKey:" <> personId.getId

createDL ::
  Id DM.Merchant ->
  DTO.DocumentVerificationConfig ->
  Id Person.Person ->
  Idfy.DLVerificationOutput ->
  Id Domain.DriverLicense ->
  Id Image.Image ->
  Maybe (Id Image.Image) ->
  Maybe Text ->
  UTCTime ->
  EncryptedHashedField 'AsEncrypted Text ->
  UTCTime ->
  Domain.DriverLicense
createDL merchantId configs driverId output id imageId1 imageId2 nameOnCard now edl expiry = do
  let classOfVehicles = maybe [] (map (.cov)) output.cov_details
  let verificationStatus = validateDLStatus configs expiry classOfVehicles now
  let verifiedName = (\n -> if '*' `T.elem` n then Nothing else Just n) =<< output.name
  let driverName = verifiedName <|> nameOnCard
  Domain.DriverLicense
    { id,
      driverId,
      documentImageId1 = imageId1,
      documentImageId2 = imageId2,
      merchantId = Just merchantId,
      driverDob = convertTextToUTC output.dob,
      driverName,
      licenseNumber = edl,
      licenseExpiry = expiry,
      classOfVehicles,
      verificationStatus,
      failedRules = [],
      consent = True,
      createdAt = now,
      updatedAt = now,
      consentTimestamp = now
    }

validateDLStatus :: DTO.DocumentVerificationConfig -> UTCTime -> [Text] -> UTCTime -> Domain.VerificationStatus
validateDLStatus configs expiry cov now = do
  case configs.supportedVehicleClasses of
    DTO.DLValidClasses [] -> Domain.INVALID
    DTO.DLValidClasses validCOVs -> do
      let validCOVsCheck = configs.vehicleClassCheckType
      let isCOVValid = foldr' (\x acc -> isValidCOVDL validCOVs validCOVsCheck x || acc) False cov
      if ((not configs.checkExpiry) || now < expiry) && isCOVValid then Domain.VALID else Domain.INVALID
    _ -> Domain.INVALID

isValidCOVDL :: [Text] -> DTO.VehicleClassCheckType -> Text -> Bool
isValidCOVDL validCOVs validCOVsCheck cov =
  checkForClass
  where
    checkForClass = foldr' (\x acc -> classCheckFunction validCOVsCheck (T.toUpper x) (T.toUpper cov) || acc) False validCOVs

cacheExtractedDl :: Id Person.Person -> Maybe Text -> Text -> Flow ()
cacheExtractedDl _ Nothing _ = return ()
cacheExtractedDl personId extractedDL operatingCity = do
  let key = dlCacheKey personId
  authTokenCacheExpiry <- getSeconds <$> asks (.authTokenCacheExpiry)
  Redis.setExp key (extractedDL, operatingCity) authTokenCacheExpiry

dlNotFoundFallback :: UTCTime -> (Text, Text) -> UTCTime -> Domain.IdfyVerification -> Person.Person -> Flow AckResponse
dlNotFoundFallback issueDate (extractedDL, operatingCity) dob verificationReq person = do
  let dlreq =
        DriverDLReq
          { driverLicenseNumber = extractedDL,
            operatingCity = operatingCity,
            driverDateOfBirth = dob,
            imageId1 = verificationReq.documentImageId1,
            imageId2 = verificationReq.documentImageId2,
            vehicleCategory = verificationReq.vehicleCategory,
            dateOfIssue = Just issueDate
          }
  void $ verifyDL False Nothing (person.id, person.merchantId, person.merchantOperatingCityId) dlreq
  return Ack
