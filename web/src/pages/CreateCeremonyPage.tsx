import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import { useParticipant } from '../hooks/useParticipant'
import { numberToRational } from '../api/types'
import type { EntropyMethod, CommitmentMode, NonParticipationPolicy, CeremonyType, BeaconSpec, IdentityMode } from '../api/types'

export default function CreateCeremonyPage() {
  const navigate = useNavigate()
  const { participantId } = useParticipant()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [question, setQuestion] = useState('')
  const [typeKind, setTypeKind] = useState<string>('CoinFlip')
  const [coinLabelA, setCoinLabelA] = useState('Heads')
  const [coinLabelB, setCoinLabelB] = useState('Tails')
  const [choices, setChoices] = useState('Option A, Option B')
  const [intMin, setIntMin] = useState(1)
  const [intMax, setIntMax] = useState(100)
  const [weightedChoices, setWeightedChoices] = useState<Array<{ label: string; weight: number }>>([
    { label: 'Option A', weight: 0.7 },
    { label: 'Option B', weight: 0.3 },
  ])
  const [method, setMethod] = useState<EntropyMethod>('OfficiantVRF')
  const [parties, setParties] = useState(2)
  const [commitMode, setCommitMode] = useState<CommitmentMode>('Immediate')
  const [deadlineMinutes, setDeadlineMinutes] = useState(60)
  const [revealMinutes, setRevealMinutes] = useState(30)
  const [nonPartPolicy, setNonPartPolicy] = useState<NonParticipationPolicy>('Exclusion')
  const [identityMode, setIdentityMode] = useState<IdentityMode>('Anonymous')
  const [beaconNetwork, setBeaconNetwork] = useState('default')

  const needsRevealParams = method === 'ParticipantReveal' || method === 'Combined'
  const needsBeacon = method === 'ExternalBeacon' || method === 'Combined'

  const parseChoiceList = () => choices.split(',').map(s => s.trim()).filter(Boolean)

  const buildCeremonyType = (): CeremonyType => {
    switch (typeKind) {
      case 'CoinFlip': return { tag: 'CoinFlip', contents: [coinLabelA, coinLabelB] }
      case 'UniformChoice':
        return { tag: 'UniformChoice', contents: parseChoiceList() }
      case 'Shuffle':
        return { tag: 'Shuffle', contents: parseChoiceList() }
      case 'IntRange':
        return { tag: 'IntRange', contents: [intMin, intMax] }
      case 'WeightedChoice':
        return { tag: 'WeightedChoice', contents: weightedChoices.map(c => [c.label, numberToRational(c.weight)] as const) }
      default: return { tag: 'CoinFlip', contents: [coinLabelA, coinLabelB] }
    }
  }

  const weightSum = weightedChoices.reduce((s, c) => s + c.weight, 0)

  const validate = (): string | null => {
    if (!question.trim()) return 'Question is required'
    if (parties < 1) return 'Required parties must be at least 1'
    if (needsRevealParams && parties === 2 && nonPartPolicy === 'DefaultSubstitution')
      return 'Default Substitution is not allowed for 2-party ceremonies'

    switch (typeKind) {
      case 'CoinFlip':
        if (!coinLabelA.trim()) return 'Coin flip: side A label is required'
        if (!coinLabelB.trim()) return 'Coin flip: side B label is required'
        if (coinLabelA.trim() === coinLabelB.trim()) return 'Coin flip: labels must be different'
        break
      case 'UniformChoice': {
        const items = parseChoiceList()
        if (items.length < 2) return 'UniformChoice: need at least 2 choices (comma-separated)'
        if (new Set(items).size !== items.length) return 'UniformChoice: all choices must be distinct'
        break
      }
      case 'Shuffle': {
        const items = parseChoiceList()
        if (items.length < 2) return 'Shuffle: need at least 2 items (comma-separated)'
        break
      }
      case 'IntRange':
        if (intMin > intMax) return 'Integer range: min must be less than or equal to max'
        break
      case 'WeightedChoice': {
        const labels = weightedChoices.map(c => c.label.trim())
        if (labels.some(l => !l)) return 'Weighted choice: all labels are required'
        if (new Set(labels).size !== labels.length) return 'Weighted choice: all labels must be distinct'
        if (weightedChoices.some(c => c.weight <= 0)) return 'Weighted choice: all weights must be positive'
        if (Math.abs(weightSum - 1) >= 0.0001) return `Weighted choice: weights must sum to 1 (currently ${weightSum})`
        break
      }
    }
    return null
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const validationError = validate()
    if (validationError) {
      setError(validationError)
      return
    }
    setLoading(true)
    setError(null)
    try {
      const now = new Date()
      const commitDeadline = new Date(now.getTime() + deadlineMinutes * 60_000).toISOString()
      const revealDeadline = needsRevealParams
        ? new Date(now.getTime() + (deadlineMinutes + revealMinutes) * 60_000).toISOString()
        : undefined

      const beaconSpec: BeaconSpec | undefined = needsBeacon
        ? { beaconNetwork, beaconRound: null, beaconFallback: { tag: 'CancelCeremony' } }
        : undefined

      const ceremony = await api.createCeremony({
        question,
        ceremony_type: buildCeremonyType(),
        entropy_method: method,
        required_parties: parties,
        commitment_mode: commitMode,
        commit_deadline: commitDeadline,
        reveal_deadline: revealDeadline,
        non_participation_policy: needsRevealParams ? nonPartPolicy : undefined,
        beacon_spec: beaconSpec,
        created_by: participantId,
        identity_mode: identityMode !== 'Anonymous' ? identityMode : undefined,
      })
      navigate(`/ceremonies/${ceremony.id}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to create ceremony')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-6">Create Ceremony</h1>

      <form onSubmit={handleSubmit} className="space-y-5">
        <Field label="Question">
          <input
            type="text"
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="e.g., Coin flip for who goes first"
            className="input"
          />
        </Field>

        <Field label="Outcome type">
          <select value={typeKind} onChange={(e) => setTypeKind(e.target.value)} className="input">
            <option value="CoinFlip">Coin Flip</option>
            <option value="UniformChoice">Uniform Choice</option>
            <option value="Shuffle">Shuffle</option>
            <option value="IntRange">Integer Range</option>
            <option value="WeightedChoice">Weighted Choice</option>
          </select>
        </Field>

        {typeKind === 'CoinFlip' && (
          <div className="flex gap-4">
            <Field label="Side A label">
              <input type="text" value={coinLabelA} onChange={(e) => setCoinLabelA(e.target.value)} placeholder="Heads" className="input" />
            </Field>
            <Field label="Side B label">
              <input type="text" value={coinLabelB} onChange={(e) => setCoinLabelB(e.target.value)} placeholder="Tails" className="input" />
            </Field>
          </div>
        )}

        {(typeKind === 'UniformChoice' || typeKind === 'Shuffle') && (
          <Field label="Choices (comma-separated)">
            <input type="text" value={choices} onChange={(e) => setChoices(e.target.value)} className="input" />
          </Field>
        )}

        {typeKind === 'IntRange' && (
          <div className="flex gap-4">
            <Field label="Min">
              <input type="number" value={intMin} onChange={(e) => setIntMin(+e.target.value)} className="input" />
            </Field>
            <Field label="Max">
              <input type="number" value={intMax} onChange={(e) => setIntMax(+e.target.value)} className="input" />
            </Field>
          </div>
        )}

        {typeKind === 'WeightedChoice' && (
          <div className="space-y-2">
            <span className="text-sm font-medium text-gray-700">Choices and weights</span>
            {weightedChoices.map((c, i) => (
              <div key={i} className="flex gap-2 items-center">
                <input
                  type="text"
                  value={c.label}
                  onChange={(e) => {
                    const next = [...weightedChoices]
                    next[i] = { ...next[i], label: e.target.value }
                    setWeightedChoices(next)
                  }}
                  placeholder="Label"
                  className="input flex-1"
                />
                <input
                  type="number"
                  step="any"
                  min={0}
                  value={c.weight}
                  onChange={(e) => {
                    const next = [...weightedChoices]
                    next[i] = { ...next[i], weight: +e.target.value }
                    setWeightedChoices(next)
                  }}
                  placeholder="Weight"
                  className="input w-24"
                />
                {weightedChoices.length > 2 && (
                  <button
                    type="button"
                    onClick={() => setWeightedChoices(weightedChoices.filter((_, j) => j !== i))}
                    className="text-red-500 hover:text-red-700 text-sm px-1"
                  >
                    Remove
                  </button>
                )}
              </div>
            ))}
            <div className="flex items-center justify-between">
              <button
                type="button"
                onClick={() => setWeightedChoices([...weightedChoices, { label: '', weight: 0 }])}
                className="text-sm text-indigo-600 hover:text-indigo-800"
              >
                + Add choice
              </button>
              <span className={`text-xs ${Math.abs(weightSum - 1) < 0.0001 ? 'text-gray-500' : 'text-red-600 font-medium'}`}>
                Sum: {weightSum.toFixed(4)}{Math.abs(weightSum - 1) >= 0.0001 && ' (must equal 1)'}
              </span>
            </div>
          </div>
        )}

        <Field label="Entropy method">
          <select value={method} onChange={(e) => setMethod(e.target.value as EntropyMethod)} className="input">
            <option value="OfficiantVRF">Server generated (simplest)</option>
            <option value="ExternalBeacon">External Beacon (drand)</option>
            <option value="ParticipantReveal">Participant Reveal (highest trust)</option>
            <option value="Combined">Combined (recommended)</option>
          </select>
        </Field>

        <Field label="Identity mode">
          <select value={identityMode} onChange={(e) => setIdentityMode(e.target.value as IdentityMode)} className="input">
            <option value="Anonymous">Anonymous (default)</option>
            <option value="SelfCertified">Self-Certified (cryptographic identity)</option>
          </select>
        </Field>

        <div className="flex gap-4">
          <Field label="Required parties">
            <input type="number" min={1} value={parties} onChange={(e) => setParties(+e.target.value)} className="input" />
          </Field>
          <Field label="Commitment mode">
            <select value={commitMode} onChange={(e) => setCommitMode(e.target.value as CommitmentMode)} className="input">
              <option value="Immediate">Immediate</option>
              <option value="DeadlineWait">Wait for Deadline</option>
            </select>
          </Field>
        </div>

        <Field label="Commit deadline (minutes from now)">
          <input type="number" min={1} value={deadlineMinutes} onChange={(e) => setDeadlineMinutes(+e.target.value)} className="input" />
        </Field>

        {needsRevealParams && (
          <>
            <Field label="Reveal deadline (minutes after commit deadline)">
              <input type="number" min={1} value={revealMinutes} onChange={(e) => setRevealMinutes(+e.target.value)} className="input" />
            </Field>
            <Field label="Non-participation policy">
              <select value={nonPartPolicy} onChange={(e) => setNonPartPolicy(e.target.value as NonParticipationPolicy)} className="input">
                <option value="Exclusion">Exclusion</option>
                <option value="DefaultSubstitution">Default Substitution</option>
                <option value="Cancellation">Cancellation</option>
              </select>
            </Field>
          </>
        )}

        {needsBeacon && (
          <Field label="Beacon network">
            <input type="text" value={beaconNetwork} onChange={(e) => setBeaconNetwork(e.target.value)} className="input" />
          </Field>
        )}

        {error && <p className="text-red-600 text-sm">{error}</p>}

        <button
          type="submit"
          disabled={loading}
          className="w-full px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50 transition-colors font-medium"
        >
          {loading ? 'Creating...' : 'Create Ceremony'}
        </button>
      </form>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="text-sm font-medium text-gray-700">{label}</span>
      <div className="mt-1">{children}</div>
    </label>
  )
}
