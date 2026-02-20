/** Generate 32 random bytes, returned as a hex string. */
export function generateEntropy(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return bytesToHex(bytes)
}

/**
 * Compute the entropy seal matching the Haskell `createSeal`:
 *   SHA-256(toASCIIBytes(ceremonyId) + toASCIIBytes(participantId) + entropyBytes)
 *
 * `entropyHex` is the hex-encoded entropy string. The seal is computed over
 * the raw bytes (after hex-decoding), matching the backend which hex-decodes
 * at the API boundary.
 */
export async function computeSeal(
  ceremonyId: string,
  participantId: string,
  entropyHex: string,
): Promise<string> {
  const encoder = new TextEncoder()
  const cidBytes = encoder.encode(ceremonyId)
  const pidBytes = encoder.encode(participantId)
  const entropyBytes = hexToBytes(entropyHex)

  const input = new Uint8Array(cidBytes.length + pidBytes.length + entropyBytes.length)
  input.set(cidBytes, 0)
  input.set(pidBytes, cidBytes.length)
  input.set(entropyBytes, cidBytes.length + pidBytes.length)

  const hash = await crypto.subtle.digest('SHA-256', input)
  return bytesToHex(new Uint8Array(hash))
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16)
  }
  return bytes
}
