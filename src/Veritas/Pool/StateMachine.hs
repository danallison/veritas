-- | Pure state machine for validation round lifecycle.
--
-- Phases: Requested -> Selecting -> Computing -> Sealing -> Revealing -> Validated/Failed
-- Terminal: Validated, Failed, Cancelled
--
-- All transition functions are pure — no IO, fully testable.
module Veritas.Pool.StateMachine
  ( submitRequesterSeal
  , recordValidatorSelection
  , submitValidatorSeal
  , submitReveal
  , finalizeRound
  ) where

import Data.List (find)
import Data.ByteString (ByteString)
import GHC.Natural (Natural)

import Veritas.Pool.Types
import Veritas.Pool.Seal (verifySeal, verifySealSignature, computeEvidenceHash)
import Veritas.Pool.Comparison (compareResults)

-- | Submit the requester's seal. Transitions Requested -> Selecting.
-- Requires the agent's public key for signature verification.
submitRequesterSeal :: ValidationRound
                    -> AgentId
                    -> ByteString       -- ^ agent's public key (32 bytes)
                    -> SealRecord
                    -> Either PoolTransitionError ValidationRound
submitRequesterSeal vr aid publicKey seal
  | vrPhase vr /= Requested = Left (InvalidRoundPhase Requested (vrPhase vr))
  | aid /= vrRequester vr = Left (AgentNotInRound aid)
  | not (verifySealSignature publicKey (srSealHash seal) (srSealSig seal)) =
      Left (SealSignatureInvalid aid)
  | otherwise = Right vr
      { vrPhase = Selecting
      , vrSeals = (aid, seal) : vrSeals vr
      }

-- | Record validator selection from drand beacon. Transitions Selecting -> Computing.
recordValidatorSelection :: ValidationRound
                         -> [PoolMember]     -- ^ selected validators
                         -> Natural          -- ^ beacon round number
                         -> ByteString       -- ^ selection proof (beacon signature)
                         -> Either PoolTransitionError ValidationRound
recordValidatorSelection vr validators beaconRound proof
  | vrPhase vr /= Selecting = Left (InvalidRoundPhase Selecting (vrPhase vr))
  | otherwise = Right vr
      { vrPhase = Computing
      , vrValidators = map pmAgentId validators
      , vrBeaconRound = Just beaconRound
      , vrSelectionProof = Just proof
      }

-- | Submit a validator's seal. When all 3 seals are in, transitions to Revealing.
-- Requires the agent's public key for signature verification.
submitValidatorSeal :: ValidationRound
                    -> AgentId
                    -> ByteString       -- ^ agent's public key (32 bytes)
                    -> SealRecord
                    -> Either PoolTransitionError ValidationRound
submitValidatorSeal vr aid publicKey seal
  | vrPhase vr /= Computing && vrPhase vr /= Sealing =
      Left (InvalidRoundPhase Computing (vrPhase vr))
  | aid `notElem` vrValidators vr = Left (AgentNotValidator aid)
  | any (\(a, _) -> a == aid) (vrSeals vr) = Left (SealAlreadySubmitted aid)
  | not (verifySealSignature publicKey (srSealHash seal) (srSealSig seal)) =
      Left (SealSignatureInvalid aid)
  | otherwise =
      let newSeals = (aid, seal) : vrSeals vr
          -- Requester seal + 2 validator seals = 3 total
          allSealed = length newSeals >= 3
          newPhase = if allSealed then Revealing else Sealing
      in Right vr
        { vrPhase = newPhase
        , vrSeals = newSeals
        }

-- | Submit a reveal (result + evidence + nonce). Verifies the seal matches.
submitReveal :: ValidationRound
             -> AgentId
             -> ByteString        -- ^ revealed result
             -> ExecutionEvidence  -- ^ revealed evidence
             -> ByteString        -- ^ revealed nonce
             -> Either PoolTransitionError ValidationRound
submitReveal vr aid result evidence nonce
  | vrPhase vr /= Revealing = Left (InvalidRoundPhase Revealing (vrPhase vr))
  | otherwise = case lookup aid (vrSeals vr) of
      Nothing -> Left (AgentNotInRound aid)
      Just seal ->
        let evidenceHash = computeEvidenceHash evidence
        in if not (verifySeal (vrFingerprint vr) aid result evidenceHash nonce (srSealHash seal))
           then Left (RevealSealMismatch aid)
           else
             let updatedSeal = seal
                   { srRevealedResult = Just result
                   , srRevealedEvidence = Just evidence
                   , srRevealedNonce = Just nonce
                   , srPhase = Revealed
                   }
                 updatedSeals = map (\(a, s) -> if a == aid then (a, updatedSeal) else (a, s)) (vrSeals vr)
             in Right vr { vrSeals = updatedSeals }

-- | Finalize a round after all reveals are in.
-- Compares results and returns the updated round plus an optional cache entry.
finalizeRound :: ValidationRound
              -> Either PoolTransitionError (ValidationRound, Maybe CacheEntry)
finalizeRound vr
  | vrPhase vr /= Revealing = Left (InvalidRoundPhase Revealing (vrPhase vr))
  | not allRevealed = Left NotAllRevealed
  | otherwise =
      let revealedResults = [(aid, res) | (aid, s) <- vrSeals vr, Just res <- [srRevealedResult s]]
          outcome = compareResults (vrComparisonMethod vr) revealedResults
      in case outcome of
        CompInconclusive -> Right (vr { vrPhase = Failed }, Nothing)
        CompUnanimous ->
          let (_, majorityResult) = head revealedResults
          in Right
              ( vr { vrPhase = Validated }
              , Just (makeCacheEntry vr majorityResult Unanimous 3)
              )
        CompMajority dissenter ->
          -- Find the majority result (any non-dissenter's result)
          case find (\(aid, _) -> aid /= dissenter) revealedResults of
            Nothing -> Right (vr { vrPhase = Failed }, Nothing)
            Just (_, majorityResult) ->
              Right
                ( vr { vrPhase = Validated }
                , Just (makeCacheEntry vr majorityResult (Majority dissenter) 2)
                )
  where
    allRevealed = all (\(_, s) -> srPhase s == Revealed) (vrSeals vr)

    makeCacheEntry :: ValidationRound -> ByteString -> ProvenanceOutcome -> Int -> CacheEntry
    makeCacheEntry vround result provOutcome agreementCount = CacheEntry
      { ceFingerprint = vrFingerprint vround
      , ceResult = result
      , ceProvenance = ResultProvenance
          { rpOutcome = provOutcome
          , rpAgreementCount = agreementCount
          , rpBeaconRound = vrBeaconRound vround
          , rpSelectionProof = vrSelectionProof vround
          , rpValidatedAt = vrCreatedAt vround  -- placeholder; actual time set by caller
          }
      , ceComputationSpec = vrComputationSpec vround
      , ceCreatedAt = vrCreatedAt vround
      , ceExpiresAt = Nothing
      }
