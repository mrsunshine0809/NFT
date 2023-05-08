module SignalMarket.Indexer.Events.SignalToken where

import           Control.Lens                                       ((^.))
import           Control.Monad                                      (unless)
import           Control.Monad.Catch                                (MonadThrow)
import           Control.Monad.Reader                               (MonadReader)
import qualified Katip                                              as K
import           Opaleye                                            (constant,
                                                                     (.==))
import           SignalMarket.Common.Class                          (MonadPG (..),
                                                                     MonadWeb3 (..))
import qualified SignalMarket.Common.Contracts.SignalToken          as Contract
import           SignalMarket.Common.EventTypes
import qualified SignalMarket.Common.Models.SignalTokenTrackedToken as TrackedToken
import qualified SignalMarket.Common.Models.SignalTokenTransfer     as Transfer
import           SignalMarket.Indexer.Config
import           SignalMarket.Indexer.Types
import           SignalMarket.Indexer.Utils                         (insert,
                                                                     update)

-- | insert a transfer event for signal tokens into postgres.
-- | In the case that this represents a newly minted signal, i.e.
-- | the from address is the null address, then we also create a signal
-- | in the signal table.

-- TODO verify / simplify this

signalTokenTransferH
  :: ( MonadPG m
     , MonadThrow m
     )
  => Event Contract.Transfer
  -> m ()
signalTokenTransferH Event{eventEventID, eventData} =
  K.katipAddNamespace "SignalToken" $ do
    K.katipAddNamespace "Transfer" $ do
      case eventData of
        Contract.Transfer{..} -> do
          let tokenID            = transferTokenId_ ^. _TokenID
              originalTokenOwner = transferFrom_ ^. _EthAddress
              newTokenOwner      = transferTo_ ^. _EthAddress
              isMinted           = originalTokenOwner == zeroAddress
          insert Transfer.transferTable $ Transfer.Transfer
            { Transfer.to = newTokenOwner
            , Transfer.from = originalTokenOwner
            , Transfer.tokenID = tokenID
            , Transfer.eventID = eventEventID
            }
          unless isMinted $ do
            let updateSignalOwner s = s { TrackedToken.owner = constant newTokenOwner }
                isTargetSignalID  s = TrackedToken.tokenID s .== constant tokenID
            _ :: TrackedToken.TrackedToken <- update TrackedToken.trackedTokenTable updateSignalOwner isTargetSignalID
            pure ()

-- | insert a newly created signal token into postgres.
signalTokenTrackedTokenH
  :: ( MonadPG m
     , MonadWeb3 m
     , MonadThrow m
     , MonadReader IndexerConfig m
     )
  => Event Contract.TrackedToken
  -> m ()
signalTokenTrackedTokenH Event{eventData, eventEventID} =
  K.katipAddNamespace "SignalToken" $ do
    K.katipAddNamespace "TrackedToken" $ do
      case eventData of
        Contract.TrackedToken{..} -> do
          let tokenID = trackedTokenTokenID_ ^. _TokenID
              cst     = trackedTokenCst_ ^. _HexBytesN
              geohash = trackedTokenGeohash_ ^. _HexBytesN
              radius  = trackedTokenRadius_ ^. _HexInteger
              stake = trackedTokenStake_ ^. _Value
              owner = trackedTokenOwner_ ^. _EthAddress
          insert TrackedToken.trackedTokenTable $ TrackedToken.TrackedToken
            { TrackedToken.nftAddress = trackedTokenNftAddress_ ^. _EthAddress
            , TrackedToken.cst = cst
            , TrackedToken.geohash = geohash
            , TrackedToken.radius = radius
            , TrackedToken.tokenID = tokenID
            , TrackedToken.owner = owner
            , TrackedToken.staked = stake
            , TrackedToken.isBurned = False
            , TrackedToken.eventID = eventEventID :: EventID
            }

signalTokenTokensUnstakedH
  :: ( MonadPG m
     , MonadThrow m
     )
  => Event Contract.TokensUnstaked
  -> m ()
signalTokenTokensUnstakedH Event{eventData} =
  K.katipAddNamespace "SignalToken" $ do
    K.katipAddNamespace "TokensUnstaked" $ do
      case eventData of
        Contract.TokensUnstaked{..} -> do
          let tokenID = tokensUnstakedTokenID_ ^. _TokenID
              updateSignal s = s { TrackedToken.isBurned = constant True
                                 , TrackedToken.staked = constant (HexInteger 0)
                                 }
              isTargetSignalID s = TrackedToken.tokenID s .== constant tokenID
          _ :: TrackedToken.TrackedToken <- update TrackedToken.trackedTokenTable updateSignal isTargetSignalID
          pure ()
