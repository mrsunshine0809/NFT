module SignalMarket.Indexer.Types where

import           Control.Lens                         (view, (^.))
import           Crypto.Hash                          (Digest, hash)
import           Crypto.Hash.Algorithms               (Keccak_256)
import           Data.ByteArray                       (Bytes, convert)
import           Data.ByteArray.Encoding              (Base (..),
                                                       convertFromBase)
import           Data.ByteArray.HexString             (HexString, toBytes)
import           Data.ByteString                      (ByteString)
import qualified Data.ByteString.Char8                as C8
import           Data.Maybe                           (fromJust)
import           Data.String.Conversions              (cs)
import qualified Data.Text                            as T
import qualified Data.Text.Lazy.Builder               as B
import qualified Data.Text.Lazy.Builder.Int           as B
import           Network.Ethereum.Api.Types           as W3
import           SignalMarket.Common.EventTypes       (EventID (..),
                                                       HexInteger (..),
                                                       _EthAddress, _HexString)
import           SignalMarket.Common.Models.RawChange (RawChange)
import           SignalMarket.Common.Models.RawChange as RC

-- | Make the raw change, eventID, and eventData from the raw Web3 response.
mkEvent
  :: W3.Change
  -> e
  -> Event e
mkEvent W3.Change{..} e =
  let li = unQuantity . fromJust $ changeLogIndex
      bh = fromJust changeBlockHash
      eid = deriveEID li bh
  in Event
      { eventEventID = eid
      , eventData = e
      , eventRawEvent = RawChange
          { RC.logIndex = HexInteger li
          , RC.transactionIndex = HexInteger . unQuantity . fromJust $ changeLogIndex
          , RC.transactionHash = fromJust changeTransactionHash ^. _HexString
          , RC.removed = False
          , RC.blockHash = bh  ^. _HexString
          , RC.blockNumber = HexInteger . unQuantity . fromJust $ changeBlockNumber
          , RC.address = changeAddress ^. _EthAddress
          , RC._data = changeData ^. _HexString
          , RC.topics = map (view _HexString) changeTopics
          , RC.eventID = eid
          }
      }

-- | useful for hashing integers
integerToBytes :: Integer -> Bytes
integerToBytes n =
  let bytes = convertFromBase Base16 . cs @_ @ByteString . T.justifyRight 64 '0' . cs . B.toLazyText . B.hexadecimal $ n
  in either error id bytes

-- | Compute the EID from the logIndex and blockHash
deriveEID :: Integer -> HexString -> EventID
deriveEID li bh =
  let digest :: Digest Keccak_256
      digest = hash (integerToBytes li <> toBytes bh)
  in EventID . view _HexString . convert . C8.take 32 . convert $ digest

data Event e = Event
  { eventEventID  :: EventID
  , eventRawEvent :: RawChange
  , eventData     :: e
  }
