// Collapsible panel showing cryptographic seal/signature details.

import { useState } from 'react'

interface CryptoField {
  label: string
  value: string
  mono?: boolean
}

interface Props {
  title: string
  fields: CryptoField[]
  onVerify?: () => void
  verifyLabel?: string
  verified?: boolean | null  // null = not checked, true = pass, false = fail
}

export default function CryptoDetailPanel({ title, fields, onVerify, verifyLabel, verified }: Props) {
  const [open, setOpen] = useState(false)

  return (
    <div className="border border-gray-200 rounded-lg mt-3">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between px-4 py-2 text-sm text-left hover:bg-gray-50"
      >
        <span className="font-medium text-gray-700">{title}</span>
        <span className="text-gray-400">{open ? '\u25B2' : '\u25BC'}</span>
      </button>
      {open && (
        <div className="px-4 pb-3 border-t border-gray-100 space-y-2">
          {fields.map((f) => (
            <div key={f.label} className="mt-2">
              <div className="text-xs text-gray-500 mb-0.5">{f.label}</div>
              <div className={`text-xs break-all ${f.mono !== false ? 'font-mono bg-gray-50 p-1.5 rounded' : ''}`}>
                {f.value}
                <button
                  onClick={() => navigator.clipboard.writeText(f.value)}
                  className="ml-2 text-indigo-500 hover:text-indigo-700 text-xs"
                  title="Copy"
                >
                  copy
                </button>
              </div>
            </div>
          ))}
          {onVerify && (
            <div className="mt-3 flex items-center gap-3">
              <button
                onClick={onVerify}
                className="text-xs px-3 py-1 bg-indigo-50 text-indigo-700 rounded hover:bg-indigo-100"
              >
                {verifyLabel ?? 'Verify Locally'}
              </button>
              {verified === true && (
                <span className="text-xs text-green-700 font-medium">Verified</span>
              )}
              {verified === false && (
                <span className="text-xs text-red-600 font-medium">Mismatch!</span>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
