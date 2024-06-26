{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Domain.Types.FarePolicy.FareBreakup where

import Domain.Types.Booking.Type
import Kernel.Prelude
import Kernel.Types.Common
import Kernel.Types.Id

data FareBreakup = FareBreakup
  { id :: Id FareBreakup,
    bookingId :: Id Booking,
    description :: Text,
    amount :: Price
  }
  deriving (Show)

data FareBreakupAPIEntity = FareBreakupAPIEntity
  { description :: Text,
    amount :: HighPrecMoney,
    amountWithCurrency :: PriceAPIEntity
  }
  deriving (Generic, Show, FromJSON, ToJSON, ToSchema)

mkFareBreakupAPIEntity :: FareBreakup -> FareBreakupAPIEntity
mkFareBreakupAPIEntity FareBreakup {..} =
  FareBreakupAPIEntity
    { amount = amount.amount,
      amountWithCurrency = mkPriceAPIEntity amount,
      ..
    }
