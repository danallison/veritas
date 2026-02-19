module Veritas.Crypto.Signatures
  ( KeyPair(..)
  , generateKeyPair
  , signMsg
  , verifyMsg
  , publicKeyBytes
  , secretKeyBytes
  ) where

import Crypto.Error (throwCryptoError)
import qualified Crypto.PubKey.Ed25519 as Ed25519
import Data.ByteArray (convert)
import Data.ByteString (ByteString)

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
