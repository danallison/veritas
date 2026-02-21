import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import { useParticipant } from '../hooks/useParticipant'
import type { EntropyMethod, CommitmentMode, NonParticipationPolicy, CeremonyType, BeaconSpec } from '../api/types'

export default function CreateCeremonyPage() {
  const navigate = useNavigate()
  const { participantId } = useParticipant()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [question, setQuestion] = useState('')
  const [typeKind, setTypeKind] = useState<string>('CoinFlip')
  const [choices, setChoices] = useState('Option A, Option B')
  const [intMin, setIntMin] = useState(1)
  const [intMax, setIntMax] = useState(100)
  const [method, setMethod] = useState<EntropyMethod>('OfficiantVRF')
  const [parties, setParties] = useState(2)
  const [commitMode, setCommitMode] = useState<CommitmentMode>('Immediate')
  const [deadlineMinutes, setDeadlineMinutes] = useState(60)
  const [revealMinutes, setRevealMinutes] = useState(30)
  const [nonPartPolicy, setNonPartPolicy] = useState<NonParticipationPolicy>('Exclusion')
  const [beaconNetwork, setBeaconNetwork] = useState('default')

  const needsRevealParams = method === 'ParticipantReveal' || method === 'Combined'
  const needsBeacon = method === 'ExternalBeacon' || method === 'Combined'

  const buildCeremonyType = (): CeremonyType => {
    switch (typeKind) {
      case 'CoinFlip': return { tag: 'CoinFlip' }
      case 'UniformChoice':
        return { tag: 'UniformChoice', contents: choices.split(',').map(s => s.trim()).filter(Boolean) }
      case 'Shuffle':
        return { tag: 'Shuffle', contents: choices.split(',').map(s => s.trim()).filter(Boolean) }
      case 'IntRange':
        return { tag: 'IntRange', contents: [intMin, intMax] }
      default: return { tag: 'CoinFlip' }
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
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
        question: question || 'Random outcome',
        ceremony_type: buildCeremonyType(),
        entropy_method: method,
        required_parties: parties,
        commitment_mode: commitMode,
        commit_deadline: commitDeadline,
        reveal_deadline: revealDeadline,
        non_participation_policy: needsRevealParams ? nonPartPolicy : undefined,
        beacon_spec: beaconSpec,
        created_by: participantId,
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
          </select>
        </Field>

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

        <Field label="Entropy method">
          <select value={method} onChange={(e) => setMethod(e.target.value as EntropyMethod)} className="input">
            <option value="OfficiantVRF">Server generated (simplest)</option>
            <option value="ExternalBeacon">External Beacon (drand)</option>
            <option value="ParticipantReveal">Participant Reveal (highest trust)</option>
            <option value="Combined">Combined (recommended)</option>
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
