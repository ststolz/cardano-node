{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}

module Cardano.Api.TxSubmit
  ( submitTx
  , TxForMode(..)
  , TxSubmitResultForMode(..)
  , renderTxSubmitResult
  ) where

import           Cardano.Prelude

import           Ouroboros.Network.Protocol.LocalTxSubmission.Type (SubmitResult (..))

import           Ouroboros.Consensus.Ledger.SupportsMempool (ApplyTxErr)

import           Ouroboros.Consensus.Byron.Ledger (ByronBlock)
import qualified Ouroboros.Consensus.Byron.Ledger as Byron
import           Ouroboros.Consensus.Cardano.Block (CardanoApplyTxErr,
                     GenTx (GenTxByron, GenTxShelley),
                     HardForkApplyTxErr (ApplyTxErrAllegra, ApplyTxErrByron, ApplyTxErrMary, ApplyTxErrShelley, ApplyTxErrWrongEra))
import           Ouroboros.Consensus.HardFork.Combinator.Degenerate
import           Ouroboros.Consensus.Shelley.Ledger (ShelleyBlock, mkShelleyTx)
import           Ouroboros.Consensus.Shelley.Protocol.Crypto (StandardCrypto)

import           Cardano.Api.TxSubmit.ErrorRender
import           Cardano.Api.Typed


data TxForMode mode where

     TxForByronMode
       :: Tx ByronEra
       -> TxForMode ByronMode

     TxForShelleyMode
       :: Tx ShelleyEra
       -> TxForMode ShelleyMode

     TxForCardanoMode
       :: Either (Tx ByronEra) (Tx ShelleyEra)
       -> TxForMode CardanoMode


data TxSubmitResultForMode mode where

     TxSubmitSuccess
       :: TxSubmitResultForMode mode

     TxSubmitFailureByronMode
       :: ApplyTxErr ByronBlock
       -> TxSubmitResultForMode ByronMode

     TxSubmitFailureShelleyMode
       :: ApplyTxErr (ShelleyBlock StandardShelley)
       -> TxSubmitResultForMode ShelleyMode

     TxSubmitFailureCardanoMode
       :: CardanoApplyTxErr StandardCrypto
       -> TxSubmitResultForMode CardanoMode

deriving instance Show (TxSubmitResultForMode ByronMode)
deriving instance Show (TxSubmitResultForMode ShelleyMode)
deriving instance Show (TxSubmitResultForMode CardanoMode)

submitTx :: forall mode block.
            LocalNodeConnectInfo mode block
         -> TxForMode mode
         -> IO (TxSubmitResultForMode mode)
submitTx connctInfo txformode =
    case (localNodeConsensusMode connctInfo, txformode) of
      (ByronMode{}, TxForByronMode (ByronTx tx)) -> do
        let genTx = DegenGenTx (Byron.ByronTx (Byron.byronIdTx tx) tx)
        result <- submitTxToNodeLocal connctInfo genTx
        case result of
          SubmitSuccess ->
            return TxSubmitSuccess
          SubmitFail (DegenApplyTxErr failure) ->
            return (TxSubmitFailureByronMode failure)

      (ByronMode{}, TxForByronMode (ShelleyTx era _)) -> case era of {}

      (ShelleyMode{}, TxForShelleyMode (ShelleyTx _ tx)) -> do
        let genTx = DegenGenTx (mkShelleyTx tx)
        result <- submitTxToNodeLocal connctInfo genTx
        case result of
          SubmitSuccess ->
            return TxSubmitSuccess
          SubmitFail (DegenApplyTxErr failure) ->
            return (TxSubmitFailureShelleyMode failure)

      (CardanoMode{}, TxForCardanoMode etx) -> do
        let genTx = case etx of
              Left  (ByronTx tx) ->
                GenTxByron (Byron.ByronTx (Byron.byronIdTx tx) tx)

              Left  (ShelleyTx era _) -> case era of {}

              Right (ShelleyTx _ tx) ->
                GenTxShelley (mkShelleyTx tx)
        result <- submitTxToNodeLocal connctInfo genTx
        case result of
          SubmitSuccess      -> return TxSubmitSuccess
          SubmitFail failure -> return (TxSubmitFailureCardanoMode failure)


renderTxSubmitResult :: TxSubmitResultForMode mode -> Text
renderTxSubmitResult res =
  case res of
    TxSubmitSuccess -> "Transaction submitted successfully."

    TxSubmitFailureByronMode err ->
      "Failed to submit Byron transaction: " <> renderApplyMempoolPayloadErr err

    TxSubmitFailureShelleyMode err ->
      -- TODO: Write render function for Shelley tx submission errors.
      "Failed to submit Shelley transaction: " <> show err

    TxSubmitFailureCardanoMode (ApplyTxErrByron err) ->
      "Failed to submit Byron transaction: " <> renderApplyMempoolPayloadErr err

    TxSubmitFailureCardanoMode (ApplyTxErrShelley err) ->
      -- TODO: Write render function for Shelley tx submission errors.
      "Failed to submit Shelley transaction: " <> show err

    TxSubmitFailureCardanoMode (ApplyTxErrMary err) ->
      "Failed to submit Mary transaction: " <> show err

    TxSubmitFailureCardanoMode (ApplyTxErrAllegra err) ->
      "Failed to submit Allegra transaction: " <> show err

    TxSubmitFailureCardanoMode (ApplyTxErrWrongEra mismatch) ->
      "Failed to submit transaction due to era mismatch: " <> show mismatch
