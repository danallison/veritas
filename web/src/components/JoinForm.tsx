import { useState } from 'react'
import { api } from '../api/client'
import { useParticipant } from '../hooks/useParticipant'
import { isValidPublicKeyHex, loadPublicKey, storePublicKey } from '../crypto/identity'

export default function JoinForm({
  ceremonyId,
  onJoined,
}: {
  ceremonyId: string
  onJoined: () => void
}) {
  const { participantId, displayName, setDisplayName } = useParticipant()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [localName, setLocalName] = useState(displayName)
  const [publicKeyInput, setPublicKeyInput] = useState(
    () => loadPublicKey(participantId) ?? '',
  )
  const [showKeypairHelp, setShowKeypairHelp] = useState(false)
  const [keygenTab, setKeygenTab] = useState<'openssl' | 'python' | 'node'>('openssl')

  const keyValid = isValidPublicKeyHex(publicKeyInput.trim())

  const handleJoin = async () => {
    const trimmedKey = publicKeyInput.trim().toLowerCase()
    if (!isValidPublicKeyHex(trimmedKey)) return
    setLoading(true)
    setError(null)
    try {
      const trimmedName = localName.trim()
      if (trimmedName) {
        setDisplayName(trimmedName)
      }

      storePublicKey(participantId, trimmedKey)

      await api.join(ceremonyId, {
        participant_id: participantId,
        public_key: trimmedKey,
        display_name: trimmedName || undefined,
      })
      onJoined()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to join')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <h3 className="font-semibold mb-2">Join this ceremony</h3>
      <p className="text-sm text-gray-600 mb-3">
        This ceremony uses self-certified identity. You need an Ed25519 keypair
        that you control. Paste your public key below.
      </p>

      <div className="mb-3">
        <button
          type="button"
          onClick={() => setShowKeypairHelp(!showKeypairHelp)}
          className="text-sm text-indigo-600 hover:text-indigo-800 font-medium"
        >
          {showKeypairHelp ? 'Hide keypair instructions' : 'How to generate a keypair'}
        </button>
        {showKeypairHelp && (
          <div className="mt-2 bg-gray-50 border border-gray-200 rounded p-3 space-y-3">
            <p className="text-xs text-gray-600">
              Generate an Ed25519 keypair using one of these methods.
              Keep your secret key safe — you will need it to sign payloads later.
            </p>
            <div className="flex gap-1 mb-2">
              {(['openssl', 'python', 'node'] as const).map((tab) => (
                <button
                  key={tab}
                  type="button"
                  onClick={() => setKeygenTab(tab)}
                  className={`text-xs px-3 py-1 rounded ${
                    keygenTab === tab
                      ? 'bg-indigo-100 text-indigo-700 font-medium'
                      : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                  }`}
                >
                  {tab === 'openssl' ? 'openssl' : tab === 'python' ? 'Python' : 'Node.js'}
                </button>
              ))}
            </div>
            <pre className="text-xs bg-gray-900 text-gray-100 p-2 rounded overflow-x-auto whitespace-pre-wrap">
{keygenTab === 'openssl' ? `# Generate and save key
openssl genpkey -algorithm ed25519 -out key.pem

# Print secret key (hex)
openssl pkey -in key.pem -noout -text 2>&1 | grep -A3 'priv:' | tail -n +2 | tr -d ' :\\n'

# Print public key (hex)
openssl pkey -in key.pem -noout -text 2>&1 | grep -A3 'pub:' | tail -n +2 | tr -d ' :\\n'`
: keygenTab === 'python' ? `# pip install pynacl
from nacl.signing import SigningKey

sk = SigningKey.generate()
print("secret:", sk.encode().hex())
print("public:", sk.verify_key.encode().hex())`
: `// npm install @noble/ed25519
const ed = require('@noble/ed25519');
(async () => {
  const sk = ed.utils.randomSecretKey();
  const pk = await ed.getPublicKeyAsync(sk);
  console.log('secret:', Buffer.from(sk).toString('hex'));
  console.log('public:', Buffer.from(pk).toString('hex'));
})();`}
            </pre>
          </div>
        )}
      </div>

      <div className="mb-3">
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Your Ed25519 public key (hex)
        </label>
        <input
          type="text"
          value={publicKeyInput}
          onChange={(e) => setPublicKeyInput(e.target.value)}
          placeholder="64 hex characters (32 bytes)"
          className="w-full px-3 py-2 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
        />
        {publicKeyInput.trim().length > 0 && !keyValid && (
          <p className="text-red-500 text-xs mt-1">
            Public key must be exactly 64 hex characters (32 bytes).
          </p>
        )}
      </div>

      <div className="mb-3">
        <input
          type="text"
          value={localName}
          onChange={(e) => setLocalName(e.target.value)}
          placeholder="Your name (optional)"
          className="w-full px-3 py-2 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
        />
      </div>

      {error && <p className="text-red-600 text-sm mb-2">{error}</p>}
      <button
        onClick={handleJoin}
        disabled={loading || !keyValid}
        className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 disabled:opacity-50 transition-colors"
      >
        {loading ? 'Joining...' : 'Join'}
      </button>
    </div>
  )
}
