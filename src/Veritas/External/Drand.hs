-- | drand HTTP client for fetching external randomness beacon values.
module Veritas.External.Drand
  ( fetchBeaconRound
  , fetchLatestBeacon
  , DrandError(..)
  , DrandResponse(..)
  , parseDrandResponse
  , drandResponseToAnchor
  ) where

import Control.Exception (try, SomeException)
import Data.Aeson (FromJSON(..), withObject, (.:))
import qualified Data.Aeson as Aeson
import Data.ByteArray.Encoding (Base(..), convertFromBase)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, getCurrentTime)
import GHC.Natural (Natural)
import Network.HTTP.Simple
  ( httpLBS, parseRequest, getResponseStatusCode, getResponseBody
  )

import Veritas.Config (DrandConfig(..))
import Veritas.Core.Types (BeaconAnchor(..))

data DrandError
  = DrandNetworkError Text
  | DrandRoundNotAvailable Natural
  | DrandParseError Text
  | DrandVerificationFailed
  deriving stock (Show)

-- | Raw JSON response from the drand API
data DrandResponse = DrandResponse
  { drRound      :: Natural
  , drRandomness :: Text    -- ^ hex-encoded randomness
  , drSignature  :: Text    -- ^ hex-encoded signature
  } deriving stock (Show, Eq)

instance FromJSON DrandResponse where
  parseJSON = withObject "DrandResponse" $ \o -> DrandResponse
    <$> o .: "round"
    <*> o .: "randomness"
    <*> o .: "signature"

-- | Parse a drand JSON response body into a DrandResponse
parseDrandResponse :: LBS.ByteString -> Either DrandError DrandResponse
parseDrandResponse bs = case Aeson.eitherDecode bs of
  Left err  -> Left (DrandParseError (T.pack err))
  Right res -> Right res

-- | Convert a parsed drand response to a BeaconAnchor
drandResponseToAnchor :: Text -> DrandResponse -> UTCTime -> Either DrandError BeaconAnchor
drandResponseToAnchor chainHash DrandResponse{..} fetchTime = do
  randomnessBytes <- decodeHex "randomness" drRandomness
  signatureBytes <- decodeHex "signature" drSignature
  pure BeaconAnchor
    { baNetwork = chainHash
    , baRound = drRound
    , baValue = randomnessBytes
    , baSignature = signatureBytes
    , baFetchedAt = fetchTime
    }

-- | Fetch a specific round from a drand network.
fetchBeaconRound :: DrandConfig
                 -> Text       -- ^ chain hash
                 -> Natural    -- ^ round number
                 -> IO (Either DrandError BeaconAnchor)
fetchBeaconRound config chainHash roundNum = do
  let url = T.unpack (drandRelayUrl config)
         <> "/" <> T.unpack chainHash
         <> "/public/" <> show roundNum
  fetchDrandUrl config chainHash url

-- | Fetch the latest round from a drand network.
fetchLatestBeacon :: DrandConfig
                  -> Text       -- ^ chain hash
                  -> IO (Either DrandError BeaconAnchor)
fetchLatestBeacon config chainHash = do
  let url = T.unpack (drandRelayUrl config)
         <> "/" <> T.unpack chainHash
         <> "/public/latest"
  fetchDrandUrl config chainHash url

-- | Internal: fetch a drand URL and parse the response into a BeaconAnchor
fetchDrandUrl :: DrandConfig -> Text -> String -> IO (Either DrandError BeaconAnchor)
fetchDrandUrl _config chainHash url = do
  result <- try @SomeException $ do
    req <- parseRequest url
    resp <- httpLBS req
    let status = getResponseStatusCode resp
    if status == 200
      then case parseDrandResponse (getResponseBody resp) of
        Left err -> pure (Left err)
        Right dr -> do
          now <- getCurrentTime
          case drandResponseToAnchor chainHash dr now of
            Left err     -> pure (Left err)
            Right anchor -> pure (Right anchor)
      else pure (Left (DrandNetworkError ("HTTP " <> T.pack (show status) <> " from " <> T.pack url)))
  case result of
    Left ex  -> pure (Left (DrandNetworkError (T.pack (show ex))))
    Right r  -> pure r

-- | Decode a hex-encoded text field
decodeHex :: Text -> Text -> Either DrandError ByteString
decodeHex fieldName hexText =
  case convertFromBase Base16 (TE.encodeUtf8 hexText) of
    Left _err -> Left (DrandParseError ("Invalid hex in " <> fieldName <> ": " <> hexText))
    Right bs  -> Right bs
