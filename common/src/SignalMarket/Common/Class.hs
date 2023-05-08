module SignalMarket.Common.Class where

import           Control.Error                 (fmapL)
import           Control.Exception             (Exception (..), toException)
import           Control.Monad.Catch           (MonadThrow (..))
import           Control.Monad.IO.Class        (MonadIO (..))
import qualified Data.Aeson                    as A
import           Data.ByteString               (ByteString)
import           Data.String                   (fromString)
import           Data.String.Conversions       (cs)
import           Data.Text                     (Text)
import           Database.PostgreSQL.Simple    (SqlError (..))
import qualified Database.PostgreSQL.Simple    as PG
import qualified Database.Redis                as Redis
import qualified Katip                         as K
import           Network.Ethereum.Api.Provider (Web3, Web3Error (..))

-- Used to log SQL errors with Katip
data SqlErrorCTX = SqlErrorCTX SqlError

instance A.ToJSON SqlErrorCTX where
  toJSON (SqlErrorCTX SqlError{..}) =
    let toText = cs @_ @Text
    in A.object [ "state" A..= toText sqlState
                , "exec_status" A..= show sqlExecStatus
                , "msg" A..= toText sqlErrorMsg
                , "detail" A..= toText sqlErrorDetail
                , "hint" A..= toText sqlErrorHint
                ]

instance K.ToObject SqlErrorCTX

instance K.LogItem SqlErrorCTX where
    payloadKeys _ _ = K.AllKeys

-- | Our basic monad class for performing postgres queries
class (K.Katip m, K.KatipContext m, MonadIO m) => MonadPG m where
    runDB' :: (PG.Connection  -> IO a) -> m (Either SqlError a)
    runDB :: (PG.Connection -> IO a) -> m a

    default runDB :: MonadThrow m => (PG.Connection  -> IO a) -> m a
    runDB q = do
      eres <- runDB' q
      case eres of
        Left sqlErr -> do
          K.katipAddContext (SqlErrorCTX sqlErr) $ do
            K.logFM K.ErrorS "Postgres action caused an exception!"
            throwM (toException sqlErr)
        Right res   -> return res

data SqlQueryException = SqlQueryException deriving (Eq, Show)

instance Exception SqlQueryException

-- | Run a query where you expect at most 1 result.
queryMaybe
  :: ( MonadPG m
     , MonadThrow m
     )
  => (PG.Connection -> IO [a])
  -> m (Maybe a)
queryMaybe q = do
  res <- runDB q
  case res of
    [] -> pure $ Nothing
    [a] -> pure $ Just a
    as -> do
      K.logFM K.ErrorS $ fromString $
        "Expected at most 1 result, got " <> show (length as) <> "!"
      throwM SqlQueryException

-- | Run a query where you expect exactly one result.
queryExact
  :: ( MonadPG m
     , MonadThrow m
     )
  => (PG.Connection -> IO [a])
  -> m a
queryExact q = do
  mRes <- queryMaybe q
  case mRes of
    Nothing -> do
      K.logFM K.ErrorS $ fromString $
        "Expected exactly 1 result, got 0!"
      throwM SqlQueryException
    Just a -> pure a


-- | Useful for logging Web3 errors via Katip.
data Web3ErrorCTX = Web3ErrorCTX Web3Error

instance A.ToJSON Web3ErrorCTX where
  toJSON (Web3ErrorCTX e) =
    let (tag :: String, message) = case e of
            JsonRpcFail msg -> ("JsonRpcFail", msg)
            ParserFail msg  -> ("ParserFail", msg)
            UserFail msg    -> ("UserFail", msg)
    in A.object [ "type" A..= tag
                , "message" A..= message
                ]

instance K.ToObject Web3ErrorCTX

instance K.LogItem Web3ErrorCTX where
    payloadKeys _ _ = K.AllKeys

-- | Basic monad class for running Web3 actions.
class (K.Katip m, K.KatipContext m, MonadIO m) => MonadWeb3 m where
    runWeb3' :: Web3 a -> m (Either Web3Error a)
    runWeb3 :: Web3 a -> m a

    default runWeb3 :: MonadThrow m => Web3 a -> m a
    runWeb3 a = do
      eres <- runWeb3' a
      case eres of
        Left e -> do
          K.katipAddContext (Web3ErrorCTX e) $ do
            K.logFM K.ErrorS "Web3 action caused an exception!"
            throwM (toException e)
        Right res   -> return res

type MonadPubSub m = (K.Katip m, K.KatipContext m, MonadIO m)

publish' :: MonadPubSub m => Redis.Connection -> ByteString -> ByteString -> m (Either Text Integer)
publish' conn channel item = do
  K.logFM K.DebugS $ fromString $ "Publishing on channel " <> cs channel
  resp <- liftIO . Redis.runRedis conn $ Redis.publish channel item
  pure $ fmapL (cs . show) $ resp

publish :: (MonadPubSub m, A.ToJSON a) => Redis.Connection -> ByteString -> a -> m ()
publish conn channel item = do
  eRes <- publish' conn channel (cs $ A.encode item)
  case eRes of
    Left err -> K.logFM K.ErrorS (fromString  . cs $ "Error in publishing to Redis: " <>  err)
    Right _ -> pure ()
