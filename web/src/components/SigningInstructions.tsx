import { useState } from 'react'

interface SigningInstructionsProps {
  payloadHex: string
  payloadDescription: string
  onSignatureSubmit: (signatureHex: string) => void
  loading: boolean
  error: string | null
}

const isValidSignatureHex = (hex: string): boolean => /^[0-9a-fA-F]{128}$/.test(hex)

export default function SigningInstructions({
  payloadHex,
  payloadDescription,
  onSignatureSubmit,
  loading,
  error,
}: SigningInstructionsProps) {
  const [signature, setSignature] = useState('')
  const [showStructure, setShowStructure] = useState(false)
  const [activeTab, setActiveTab] = useState<'openssl' | 'python' | 'node'>('openssl')
  const [copied, setCopied] = useState(false)

  const trimmedSig = signature.trim()
  const sigValid = isValidSignatureHex(trimmedSig)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(payloadHex)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const handleSubmit = () => {
    if (sigValid) {
      onSignatureSubmit(trimmedSig.toLowerCase())
    }
  }

  const opensslSnippet = `# Write payload to a temp file
echo -n "${payloadHex}" | xxd -r -p > /tmp/payload.bin

# Sign with your key (replace key.pem with your key file)
openssl pkeyutl -sign -inkey key.pem -rawin -in /tmp/payload.bin | xxd -p | tr -d '\\n'

rm /tmp/payload.bin`

  const pythonSnippet = `# pip install pynacl
from nacl.signing import SigningKey

sk = SigningKey(bytes.fromhex("YOUR_SECRET_KEY_HEX"))
payload = bytes.fromhex("${payloadHex}")
print(sk.sign(payload).signature.hex())`

  const nodeSnippet = `// npm install @noble/ed25519
const ed = require('@noble/ed25519');
const sk = 'YOUR_SECRET_KEY_HEX';
(async () => {
  const sig = await ed.signAsync(
    Buffer.from('${payloadHex}', 'hex'),
    Buffer.from(sk, 'hex')
  );
  console.log(Buffer.from(sig).toString('hex'));
})();`

  return (
    <div className="space-y-4">
      <div>
        <button
          type="button"
          onClick={() => setShowStructure(!showStructure)}
          className="text-sm text-indigo-600 hover:text-indigo-800 font-medium"
        >
          {showStructure ? 'Hide' : 'Show'} payload structure
        </button>
        {showStructure && (
          <pre className="mt-2 text-xs bg-gray-50 p-3 rounded border border-gray-200 overflow-x-auto whitespace-pre-wrap">
            {payloadDescription}
          </pre>
        )}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Payload to sign (hex)
        </label>
        <div className="relative">
          <code className="block text-xs bg-gray-50 p-3 rounded border border-gray-200 break-all select-all">
            {payloadHex}
          </code>
          <button
            type="button"
            onClick={handleCopy}
            className="absolute top-1 right-1 text-xs px-2 py-1 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
          >
            {copied ? 'Copied' : 'Copy'}
          </button>
        </div>
      </div>

      <div>
        <p className="text-sm font-medium text-gray-700 mb-2">
          Example signing commands
        </p>
        <div className="flex gap-1 mb-2">
          {(['openssl', 'python', 'node'] as const).map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setActiveTab(tab)}
              className={`text-xs px-3 py-1 rounded ${
                activeTab === tab
                  ? 'bg-indigo-100 text-indigo-700 font-medium'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {tab === 'openssl' ? 'openssl' : tab === 'python' ? 'Python' : 'Node.js'}
            </button>
          ))}
        </div>
        <pre className="text-xs bg-gray-900 text-gray-100 p-3 rounded overflow-x-auto whitespace-pre-wrap">
          {activeTab === 'openssl' ? opensslSnippet : activeTab === 'python' ? pythonSnippet : nodeSnippet}
        </pre>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Paste your signature (128 hex characters)
        </label>
        <textarea
          value={signature}
          onChange={(e) => setSignature(e.target.value)}
          placeholder="Ed25519 signature hex (128 characters)"
          rows={2}
          className="w-full px-3 py-2 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
        />
        {trimmedSig.length > 0 && !sigValid && (
          <p className="text-red-500 text-xs mt-1">
            Signature must be exactly 128 hex characters (64 bytes).
          </p>
        )}
      </div>

      {error && <p className="text-red-600 text-sm">{error}</p>}

      <button
        type="button"
        onClick={handleSubmit}
        disabled={!sigValid || loading}
        className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 disabled:opacity-50 transition-colors"
      >
        {loading ? 'Submitting...' : 'Submit Signature'}
      </button>
    </div>
  )
}
