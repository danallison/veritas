import { useState } from 'react'

export default function CopyLinkButton({ ceremonyId }: { ceremonyId: string }) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    const url = `${window.location.origin}/ceremonies/${ceremonyId}`
    await navigator.clipboard.writeText(url)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <button
      onClick={handleCopy}
      className="text-sm px-3 py-1 rounded border border-gray-300 hover:bg-gray-100 transition-colors"
    >
      {copied ? 'Copied!' : 'Copy Link'}
    </button>
  )
}
