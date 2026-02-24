import { useState, useEffect } from 'react'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function isValidUuid(s: string): boolean {
  return UUID_RE.test(s)
}

interface CeremonyInputProps {
  initialId: string
  onLoad: (ceremonyId: string) => void
  loading?: boolean
}

export default function CeremonyInput({ initialId, onLoad, loading }: CeremonyInputProps) {
  const [value, setValue] = useState(initialId)
  useEffect(() => { setValue(initialId) }, [initialId])
  const trimmed = value.trim()
  const valid = trimmed === '' || isValidUuid(trimmed)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (trimmed && isValidUuid(trimmed)) onLoad(trimmed)
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-1">
      <div className="flex items-center gap-3">
        <label htmlFor="ceremony-id" className="text-sm font-medium text-gray-700 shrink-0">
          Ceremony ID
        </label>
        <input
          id="ceremony-id"
          type="text"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="Enter a ceremony UUID..."
          className={`flex-1 px-3 py-1.5 text-sm font-mono border rounded focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 ${
            !valid ? 'border-red-400 bg-red-50' : 'border-gray-300'
          }`}
        />
        <button
          type="submit"
          disabled={!trimmed || !valid || loading}
          className="px-4 py-1.5 text-sm font-medium rounded bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {loading ? 'Loading...' : 'Load'}
        </button>
      </div>
      {!valid && (
        <p className="text-xs text-red-600 ml-[5.5rem]">
          Must be a valid UUID (e.g. 579de1ff-a705-4a66-b161-bdd7a0509a6c)
        </p>
      )}
    </form>
  )
}
