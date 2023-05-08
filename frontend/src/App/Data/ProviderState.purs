module App.Data.ProviderState where

import Prelude

import App.Ethereum.Provider (Connectivity(..), Provider', Unknown)
import App.MarketClient.Types (Contracts)
import Data.Maybe (Maybe(..))
import Network.Ethereum.Web3 (Address, Provider)


data State
  = Unknown
  | NotInjected
  | Injected { loading :: Boolean }
  | Rejected (Provider' Unknown)
  | Enabled
      { connectivity :: Connectivity
      , provider :: Provider
      , contracts :: Contracts
      }


type ConnectedState = { userAddress :: Address, provider :: Provider, contracts :: Contracts }

viewConnectedState :: State -> Maybe ConnectedState
viewConnectedState
  (Enabled
    { connectivity: (Connected {userAddress})
    , provider
    , contracts
    }) = Just {userAddress, provider, contracts}
viewConnectedState _ = Nothing


partialEq :: State -> State -> Boolean
partialEq a b = case a, b of
  Unknown, Unknown -> true
  Unknown, _ -> false
  NotInjected, NotInjected -> true
  NotInjected, _ -> false
  Injected c, Injected c' -> c' == c
  Injected _, _ -> false
  Rejected _, Rejected _ -> true
  Rejected _, _ -> false
  Enabled c, Enabled c' -> c'.connectivity == c.connectivity
  Enabled c, _ -> false
