module Deploy.Main where

import Prelude

import Chanterelle.Deploy (deployContract)
import Chanterelle.Internal.Deploy (DeployReceipt)
import Chanterelle.Internal.Types (DeployM, DeployConfig(..), ContractConfig, NoArgs, noArgs, constructorNoArgs)
import Control.Monad.Reader.Class (ask)
import Data.Lens ((?~))
import Data.Maybe (fromJust)
import Network.Ethereum.Core.BigNumber (decimal, parseBigNumber)
import Network.Ethereum.Web3 (Address, _from, _gas, _gasPrice, defaultTransactionOptions)
import Contracts.SignalMarket as SignalMarket
import Partial.Unsafe (unsafePartial)
import Contracts.SignalToken as SignalToken

deploy :: DeployM Unit
deploy = void deployScript

-- `chanterelle` - required for deployment
simpleStorageConfig :: ContractConfig NoArgs
simpleStorageConfig =
  { -- solc build artifact (chanterelle compiled)
    filepath: "./build/SimpleStorage.json"
  , name: "SimpleStorage"
  , constructor: constructorNoArgs
  , unvalidatedArgs: noArgs
  }

-- foamtoken also has no args
foamTokenConfig :: ContractConfig NoArgs
foamTokenConfig =
  {
    filepath: "./build/FoamToken.json"
  , name: "FoamToken"
  , constructor : constructorNoArgs
  , unvalidatedArgs : noArgs
  }

-- when constructor has arguments
type SignalToken = (_token :: Address)

makeSignalTokenConfig :: Record SignalToken -> ContractConfig SignalToken
makeSignalTokenConfig { _token } =
  {
    filepath: "./build/SignalToken.json"
  , name: "SignalToken"
  , constructor: SignalToken.constructor
  , unvalidatedArgs: pure { _token }
  }

type SignalMarket = (_signalToken :: Address, _foamToken :: Address)

makeSignalMarketConfig :: Record SignalMarket -> ContractConfig SignalMarket
makeSignalMarketConfig { _signalToken, _foamToken } =
  {
    filepath: "./build/SignalMarket.json"
  , name: "SignalMarket"
  -- from chanterelle-generated PS files
  , constructor: SignalMarket.constructor
  -- required to be a record for the V monad
  , unvalidatedArgs: pure { _signalToken, _foamToken }
  }

-- like what is this
type DeployResults =
  ( simpleStorage :: DeployReceipt NoArgs
  , foamToken :: DeployReceipt NoArgs
  , signalToken :: DeployReceipt SignalToken
  , signalMarket :: DeployReceipt SignalMarket
  , tokenFaucet :: Address
  )

-- web3 connection
-- npm run build this
-- then chanterelle deploy ./output/blah/index.js
deployScript :: DeployM (Record DeployResults)
deployScript = do
  deployCfg@(DeployConfig {primaryAccount, provider}) <- ask
  let bigGasLimit = unsafePartial fromJust $ parseBigNumber decimal "6712388"
      bigGasPrice = unsafePartial fromJust $ parseBigNumber decimal "10000000000"
      txOpts = defaultTransactionOptions # _from ?~ primaryAccount
                                         # _gas ?~ bigGasLimit
                                         # _gasPrice ?~ bigGasPrice
  -- deploy simple storage
  simpleStorage <- deployContract txOpts simpleStorageConfig
  -- deploy the FoamToken contract
  foamToken <- deployContract txOpts foamTokenConfig
  -- deploy the SignalToken contract
  let signalTokenCfg = makeSignalTokenConfig { _token: foamToken.deployAddress }
  signalToken <- deployContract txOpts signalTokenCfg
  -- deploy the SignalMarket contract
  signalMarket <- deployContract txOpts $
                  makeSignalMarketConfig { _signalToken: signalToken.deployAddress
                                         , _foamToken: foamToken.deployAddress
                                         }
  pure { simpleStorage, foamToken, signalToken, signalMarket, tokenFaucet: primaryAccount }
