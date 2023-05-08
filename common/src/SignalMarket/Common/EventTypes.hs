module SignalMarket.Common.EventTypes where

import           Control.Lens                         (Iso', from, iso, to,
                                                       view, (^.))
import qualified Data.Aeson                           as A
import qualified Data.ByteArray.HexString             as Hx
import           Data.ByteArray.Sized                 (unsafeSizedByteArray)
import           Data.Char                            (isHexDigit)
import           Data.Profunctor
import qualified Data.Profunctor.Product.Default      as D
import           Data.Scientific                      (Scientific)
import           Data.Solidity.Prim.Address           (Address, fromHexString,
                                                       toHexString)
import           Data.Solidity.Prim.Bytes             (BytesN)
import           Data.Solidity.Prim.Int               (UIntN)
import           Data.String                          (fromString)
import           Data.String.Conversions              (cs)
import           Data.Swagger                         (SwaggerType (..),
                                                       ToParamSchema (..),
                                                       ToSchema (..),
                                                       defaultSchemaOptions,
                                                       genericDeclareNamedSchema)
import           Data.Text                            (Text)
import qualified Data.Text                            as T
import qualified Data.Text.Lazy                       as TL (toStrict)
import qualified Data.Text.Lazy.Builder               as B
import qualified Data.Text.Lazy.Builder.Int           as B
import qualified Data.Text.Read                       as R
import qualified Database.PostgreSQL.Simple.FromField as FF
import qualified GHC.Generics                         as GHC (Generic)
import           GHC.TypeLits
import           Opaleye                              (Column, Constant,
                                                       SqlNumeric, SqlText,
                                                       ToFields)
import qualified Opaleye.Internal.RunQuery            as IQ
import           Opaleye.RunQuery                     (QueryRunnerColumnDefault,
                                                       fieldQueryRunnerColumn)

import           Opaleye.Column                       (unsafeCast)


--------------------------------------------------------------------------------
-- | The basic type for any integer like data in Ethereum (e.g. block number, uint245, int8, etc.)
-- | It serializes in JSON to a string representation of a hex encoded integer,
-- | making it safe to return to Javascript clients.
newtype HexInteger = HexInteger Integer deriving (Eq, Show, Ord, GHC.Generic, Num, Enum, Real, Integral)

instance ToParamSchema HexInteger

hexIntegerToText :: HexInteger -> Text
hexIntegerToText (HexInteger n) = TL.toStrict . (<>) "0x" . B.toLazyText $ B.hexadecimal n

hexIntegerFromText :: Text -> Either String HexInteger
hexIntegerFromText t = case R.hexadecimal . maybeTrim $ t of
    Right (x, "") -> Right (HexInteger x)
    _             -> Left "Unable to parse HexInteger"
  where
    maybeTrim txt = if T.take 2 txt == "0x" then T.drop 2 txt else txt

instance A.ToJSON HexInteger where
    toJSON = A.toJSON . hexIntegerToText

instance ToSchema HexInteger where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy

instance A.FromJSON HexInteger where
    parseJSON (A.String v) = either fail pure . hexIntegerFromText $ v
    parseJSON _ = fail "HexInteger may only be parsed from a JSON String"

instance IQ.QueryRunnerColumnDefault SqlNumeric HexInteger where
  defaultFromField = HexInteger . truncate . toRational <$> fieldQueryRunnerColumn @Scientific

instance D.Default ToFields HexInteger (Column SqlNumeric) where
  def = lmap (\(HexInteger a) -> fromInteger @Scientific a) D.def

-- | Safely convert to or from a Hex integer to any size uint
_HexInteger :: (KnownNat n, n <= 256) => Iso' (UIntN n) HexInteger
_HexInteger = iso (HexInteger . toInteger) (\(HexInteger n) -> fromInteger n)

--------------------------------------------------------------------------------

-- | Represents some quantity of tokens
newtype Value = Value HexInteger deriving (Eq, Ord, Show, GHC.Generic, Num, Enum, Real, Integral, A.ToJSON, A.FromJSON)

instance ToSchema Value where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy

instance D.Default ToFields Value (Column SqlNumeric) where
  def = lmap (\(Value a) -> a) D.def

_Value :: (KnownNat n, n <= 256) => Iso' (UIntN n) Value
_Value = iso (view $ _HexInteger . to Value) (view $ to (\(Value v) -> v) . from _HexInteger)

instance IQ.QueryRunnerColumnDefault SqlNumeric Value where
  defaultFromField = Value . HexInteger . truncate . toRational <$> fieldQueryRunnerColumn @Scientific

--------------------------------------------------------------------------------

-- | Represents the unique identifier of a sale in the marketplace contract.
newtype SaleID = SaleID HexInteger deriving (Eq, Ord, Show, GHC.Generic, IQ.QueryRunnerColumnDefault SqlNumeric, A.ToJSON, A.FromJSON)

instance ToParamSchema SaleID
instance ToSchema SaleID where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy


_SaleID :: (KnownNat n, n <= 256) => Iso' (UIntN n) SaleID
_SaleID = iso (view $ _HexInteger . to SaleID) (view $ to (\(SaleID v) -> v) . from _HexInteger)

instance D.Default ToFields SaleID (Column SqlNumeric) where
  def = lmap (\(SaleID a) -> a) D.def

--------------------------------------------------------------------------------

-- | Represents the unique identifier of a Signal Token
newtype TokenID = TokenID HexInteger deriving (Eq, Ord, Show, GHC.Generic, IQ.QueryRunnerColumnDefault SqlNumeric, A.ToJSON, A.FromJSON)

instance ToParamSchema TokenID
instance ToSchema TokenID where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy


_TokenID :: (KnownNat n, n <= 256) => Iso' (UIntN n) TokenID
_TokenID = iso (view $ _HexInteger . to TokenID) (view $ to (\(TokenID v) -> v) . from _HexInteger)

instance D.Default ToFields TokenID (Column SqlNumeric) where
  def = lmap (\(TokenID a) -> a) D.def

--------------------------------------------------------------------------------

-- | The base type for anyting stringlike in Ethereum (including address, bytes, hashes, etc.)
newtype HexString = HexString Text
  deriving (Eq, Read, Show, Ord, GHC.Generic)

instance ToParamSchema HexString
instance ToSchema HexString where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy


instance A.FromJSON HexString where
  parseJSON = A.withText "HexString" $ \txt ->
    either fail pure $ parseHexString txt

parseHexString :: Text -> Either String HexString
parseHexString = parse . T.toLower . trim0x
  where
    trim0x s  | T.take 2 s == "0x" = T.drop 2 s
              | otherwise = s
    parse txt | T.all isHexDigit txt && (T.length txt `mod` 2 == 0) = Right $ HexString txt
              | otherwise            = Left $ "Failed to parse text as HexString: " <> show txt

unsafeParseHexString :: Text -> HexString
unsafeParseHexString = either (error . cs) id . parseHexString

displayHexString :: HexString -> Text
displayHexString (HexString hex) = "0x" <> hex

instance A.ToJSON HexString where
  toJSON = A.String . displayHexString

instance QueryRunnerColumnDefault SqlText HexString where
  queryRunnerColumnDefault = fromRightWithError . parseHexString <$> fieldQueryRunnerColumn @Text
    where
      fromRightWithError eHex = case eHex of
        Left err  -> error $ "Error Parsing HexString from DB: " <> err
        Right res -> res

instance D.Default ToFields HexString (Column SqlText) where
  def = lmap (\(HexString a) -> a) D.def

-- | convert safely to or from the Web3.HexString type.
_HexString :: Iso' Hx.HexString HexString
_HexString = iso (unsafeParseHexString . Hx.toText)
                 (\(HexString hx) -> fromString $ T.unpack hx)


--------------------------------------------------------------------------------
-- | A unique identifier for an EVM log entry, hash(blockHash,logIndex)
newtype EventID = EventID HexString deriving (Eq, Ord, Show, GHC.Generic, QueryRunnerColumnDefault SqlText, A.ToJSON, A.FromJSON)

instance ToSchema EventID where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy


instance D.Default ToFields EventID (Column SqlText) where
  def = lmap (\(EventID a) -> a) D.def

--------------------------------------------------------------------------------

-- | Represents any size bytes in solidity.
newtype ByteNValue = ByteNValue HexString deriving (Eq, Ord, Show, GHC.Generic, IQ.QueryRunnerColumnDefault SqlText, A.ToJSON, A.FromJSON)
instance ToSchema ByteNValue where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy


instance D.Default ToFields ByteNValue (Column SqlText) where
  def = lmap (\(ByteNValue a) -> a) D.def

-- | A safe conversion function to for from any size bytes
_HexBytesN :: (KnownNat n, n <= 32) => Iso' (BytesN n) ByteNValue
_HexBytesN = iso (ByteNValue . view _HexString . Hx.fromBytes) (\(ByteNValue bs) -> bs ^. from _HexString . to Hx.toBytes . to unsafeSizedByteArray)

displayByteNValue :: ByteNValue -> Text
displayByteNValue (ByteNValue v) = displayHexString v

--------------------------------------------------------------------------------

-- | Represents an ethereum address
newtype EthAddress = EthAddress HexString deriving (Eq, Ord, Show, GHC.Generic, QueryRunnerColumnDefault SqlText, A.ToJSON, A.FromJSON)
instance ToSchema EthAddress where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy


instance ToParamSchema EthAddress
instance D.Default ToFields EthAddress (Column SqlText) where
  def = lmap (\(EthAddress a) -> a) D.def

-- | Safe conversion function to or from Web3.Address
_EthAddress :: Iso' Address EthAddress
_EthAddress = iso (EthAddress . view _HexString . toHexString)
  (\(EthAddress a) -> either error id $ fromHexString $ view (from _HexString) a)

zeroAddress :: EthAddress
zeroAddress = either (error . ("Failed to create the zero address: " ++)) id $ EthAddress <$> parseHexString "0x0000000000000000000000000000000000000000"

--------------------------------------------------------------------------------
-- the way we do enums is vendered from https://hackage.haskell.org/package/composite-opaleye-0.6.0.0/docs/Composite-Opaleye-TH.html#v:deriveOpaleyeEnum

-- | Represents the sale status of a signal in the marketplace. Note that in case
-- | of SSComplete or SSUnlisted, the sale is actually no longer in the marketplace.
data SaleStatus = SSActive | SSComplete | SSUnlisted deriving (Eq, Show, GHC.Generic)

instance ToParamSchema SaleStatus
instance ToSchema SaleStatus where
  declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy

data SqlSaleStatus

instance FF.FromField SaleStatus where
  fromField f mbs = do
    tname <- FF.typename f
    case mbs of
      _ | tname /= "salestatus" -> FF.returnError FF.Incompatible f ""
      Just "active" -> pure SSActive
      Just "complete" -> pure SSComplete
      Just "unlisted" -> pure SSUnlisted
      Just other -> FF.returnError FF.ConversionFailed f ("Unexpected myenum value: " <> cs other)
      Nothing    -> FF.returnError FF.UnexpectedNull f ""

instance QueryRunnerColumnDefault SqlSaleStatus SaleStatus where
  queryRunnerColumnDefault = fieldQueryRunnerColumn

instance D.Default Constant SaleStatus (Column SqlSaleStatus) where
  def = dimap saleStatusToText (unsafeCast "salestatus")
          (D.def :: Constant Text (Column SqlText))

instance A.FromJSON SaleStatus where
  parseJSON = A.withText "SaleStatus" $ \case
      "active" -> pure SSActive
      "complete" -> pure SSComplete
      "unlisted" -> pure SSUnlisted
      _ -> fail "SaleStatus must be \"active\", \"complete\", or \"unlisted\"."

instance A.ToJSON SaleStatus where
  toJSON = A.toJSON . saleStatusToText

saleStatusToText :: SaleStatus -> Text
saleStatusToText = \case
  SSActive -> "active"
  SSComplete -> "complete"
  SSUnlisted  -> "unlisted"

parseHStatus :: Text -> Either String SaleStatus
parseHStatus "active"   = Right SSActive
parseHStatus "complete" = Right SSComplete
parseHStatus "unlisted" = Right SSUnlisted
parseHStatus txt        = Left $ "Invalid status token" <> show txt
