module Veritas.Crypto.Signatures
  ( KeyPair(..)
  , generateKeyPair
  , loadOrGenerateKeyPair
  , signMsg
  , verifyMsg
  , publicKeyBytes
  , secretKeyBytes
  ) where

import Crypto.Error (throwCryptoError)
import qualified Crypto.PubKey.Ed25519 as Ed25519
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import System.Directory (doesFileExist)
import System.Posix.Files (setFileMode)

data KeyPair = KeyPair
  { kpSecret :: Ed25519.SecretKey
  , kpPublic :: Ed25519.PublicKey
  }

-- | Generate a new Ed25519 key pair (uses system randomness)
generateKeyPair :: IO KeyPair
generateKeyPair = do
  sk <- Ed25519.generateSecretKey
  let pk = Ed25519.toPublic sk
  pure KeyPair { kpSecret = sk, kpPublic = pk }

-- | Load a key pair from a file, or generate one and save it.
-- If no path given, generate an ephemeral key (not persisted).
loadOrGenerateKeyPair :: Maybe FilePath -> IO KeyPair
loadOrGenerateKeyPair Nothing = generateKeyPair
loadOrGenerateKeyPair (Just path) = do
  exists <- doesFileExist path
  if exists
    then loadKeyPair path
    else do
      kp <- generateKeyPair
      saveKeyPair path kp
      pure kp

-- | Save a key pair to a file (32 bytes secret ++ 32 bytes public).
-- Sets file permissions to 0600.
saveKeyPair :: FilePath -> KeyPair -> IO ()
saveKeyPair path kp = do
  let bytes = secretKeyBytes (kpSecret kp) <> publicKeyBytes (kpPublic kp)
  BS.writeFile path bytes
  setFileMode path 0o600

-- | Load a key pair from a file (expects 64 bytes: 32 secret ++ 32 public).
loadKeyPair :: FilePath -> IO KeyPair
loadKeyPair path = do
  bytes <- BS.readFile path
  let (skBytes, pkBytes) = BS.splitAt 32 bytes
      sk = throwCryptoError (Ed25519.secretKey skBytes)
      pk = throwCryptoError (Ed25519.publicKey pkBytes)
  pure KeyPair { kpSecret = sk, kpPublic = pk }

-- | Sign a message with a secret key
signMsg :: Ed25519.SecretKey -> Ed25519.PublicKey -> ByteString -> ByteString
signMsg sk pk msg = convert (Ed25519.sign sk pk msg)

-- | Verify a signature against a public key and message
verifyMsg :: ByteString -> ByteString -> ByteString -> Bool
verifyMsg pkBytes sigBytes msg =
  let pk = throwCryptoError (Ed25519.publicKey pkBytes)
      sig = throwCryptoError (Ed25519.signature sigBytes)
  in Ed25519.verify pk msg sig

-- | Extract raw bytes from a public key
publicKeyBytes :: Ed25519.PublicKey -> ByteString
publicKeyBytes = convert

-- | Extract raw bytes from a secret key
secretKeyBytes :: Ed25519.SecretKey -> ByteString
secretKeyBytes = convert
