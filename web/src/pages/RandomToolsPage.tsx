import { useState } from 'react'
import { api } from '../api/client'

export default function RandomToolsPage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Random Tools</h1>
      <p className="text-gray-600 text-sm">
        Quick standalone randomness powered by Veritas. No ceremony required.
      </p>
      <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <CoinFlipCard />
        <RandomIntCard />
        <RandomUUIDCard />
      </div>
    </div>
  )
}

function CoinFlipCard() {
  const [result, setResult] = useState<boolean | null>(null)
  const [loading, setLoading] = useState(false)

  const flip = async () => {
    setLoading(true)
    try {
      const data = await api.flipCoin()
      setResult(data.result)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card title="Coin Flip">
      {result !== null && (
        <p className="text-3xl font-bold text-center py-4">
          {result ? 'Heads' : 'Tails'}
        </p>
      )}
      <button onClick={flip} disabled={loading} className="btn w-full">
        {loading ? 'Flipping...' : 'Flip'}
      </button>
    </Card>
  )
}

function RandomIntCard() {
  const [min, setMin] = useState(1)
  const [max, setMax] = useState(100)
  const [result, setResult] = useState<number | null>(null)
  const [loading, setLoading] = useState(false)

  const generate = async () => {
    setLoading(true)
    try {
      const data = await api.randomInt(min, max)
      setResult(data.result)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card title="Random Integer">
      <div className="flex gap-2 mb-3">
        <label className="flex-1">
          <span className="text-xs text-gray-500">Min</span>
          <input type="number" value={min} onChange={(e) => setMin(+e.target.value)} className="input text-sm" />
        </label>
        <label className="flex-1">
          <span className="text-xs text-gray-500">Max</span>
          <input type="number" value={max} onChange={(e) => setMax(+e.target.value)} className="input text-sm" />
        </label>
      </div>
      {result !== null && (
        <p className="text-3xl font-bold text-center py-4">{result}</p>
      )}
      <button onClick={generate} disabled={loading} className="btn w-full">
        {loading ? 'Generating...' : 'Generate'}
      </button>
    </Card>
  )
}

function RandomUUIDCard() {
  const [result, setResult] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const generate = async () => {
    setLoading(true)
    try {
      const data = await api.randomUUID()
      setResult(data.result)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card title="Random UUID">
      {result && (
        <p className="text-sm font-mono text-center py-4 break-all">{result}</p>
      )}
      <button onClick={generate} disabled={loading} className="btn w-full">
        {loading ? 'Generating...' : 'Generate'}
      </button>
    </Card>
  )
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <h3 className="font-semibold mb-3">{title}</h3>
      {children}
    </div>
  )
}
