import { useReducer, useState, useEffect } from 'react'
import { poolApi } from '../api/poolClient'
import type {
  ComputationSpec,
  ExecutionEvidence,
  PoolResponse,
  RoundStatusResponse,
  CacheEntryResponse,
} from '../api/poolTypes'
import {
  generateKeyPair,
  createSealData,
  computeFingerprint,
  toHex,
  createSeal,
  computeEvidenceHash,
  type KeyPair,
} from '../crypto/poolSeal'
import { simulatedCompute } from '../utils/simulatedCompute'
import { formatUsd } from '../utils/costs'
import PoolPhaseIndicator from '../components/pool/PoolPhaseIndicator'
import CryptoDetailPanel from '../components/pool/CryptoDetailPanel'
import AgentCard from '../components/pool/AgentCard'
import CostComparisonCard from '../components/pool/CostComparisonCard'

// --- Agent definitions ---
const ORG_NAMES = [
  { name: 'Apex Analytics', principal: 'apex-analytics' },
  { name: 'Bastion Research', principal: 'bastion-research' },
  { name: 'Cipher Systems', principal: 'cipher-systems' },
  { name: 'Delta Insights', principal: 'delta-insights' },
  { name: 'Echo Networks', principal: 'echo-networks' },
  { name: 'Forge Intelligence', principal: 'forge-intelligence' },
  { name: 'Grid Dynamics', principal: 'grid-dynamics' },
]

interface AgentState {
  id: string
  name: string
  principal: string
  keypair: KeyPair | null
  publicKeyHex: string
  registered: boolean
  role: 'requester' | 'validator' | 'consumer'
  // Seal data (filled during protocol)
  result: Uint8Array | null
  evidence: ExecutionEvidence | null
  nonce: Uint8Array | null
  sealHash: string | null
  sealSig: string | null
  fingerprint: string | null
  evidenceHash: string | null
  // Reveal/cache state
  revealed: boolean
  cacheResult: CacheEntryResponse | null
}

interface DemoState {
  step: number
  pool: PoolResponse | null
  agents: AgentState[]
  spec: ComputationSpec
  fingerprintHex: string
  roundId: string | null
  roundPhase: string | null
  roundResponses: RoundStatusResponse[]
  comparisonOutcome: string | null
  error: string | null
  loading: string | null
}

type Action =
  | { type: 'SET_POOL'; pool: PoolResponse }
  | { type: 'SET_AGENTS'; agents: AgentState[] }
  | { type: 'UPDATE_AGENT'; index: number; update: Partial<AgentState> }
  | { type: 'SET_SPEC'; spec: ComputationSpec; fingerprint: string }
  | { type: 'SET_ROUND'; roundId: string; phase: string }
  | { type: 'ADD_ROUND_RESPONSE'; response: RoundStatusResponse }
  | { type: 'SET_ROUND_PHASE'; phase: string }
  | { type: 'SET_COMPARISON_OUTCOME'; outcome: string }
  | { type: 'SET_STEP'; step: number }
  | { type: 'SET_ERROR'; error: string | null }
  | { type: 'SET_LOADING'; loading: string | null }

const DEFAULT_SPEC: ComputationSpec = {
  provider: 'anthropic',
  model: 'claude-sonnet-4-20250514',
  temperature: 0,
  seed: 42,
  max_tokens: 1024,
  system_prompt: 'You are a financial risk analyst. Provide a structured risk assessment.',
  user_prompt: 'Analyze the risk profile of a diversified portfolio containing 60% equities, 30% bonds, and 10% alternatives. Provide risk score (1-10), key factors, and recommendation.',
  structured_output: { type: 'risk_assessment', fields: ['score', 'factors', 'recommendation'] },
  input_refs: [],
}

function reducer(state: DemoState, action: Action): DemoState {
  switch (action.type) {
    case 'SET_POOL': return { ...state, pool: action.pool }
    case 'SET_AGENTS': return { ...state, agents: action.agents }
    case 'UPDATE_AGENT': {
      const agents = [...state.agents]
      agents[action.index] = { ...agents[action.index], ...action.update }
      return { ...state, agents }
    }
    case 'SET_SPEC': return { ...state, spec: action.spec, fingerprintHex: action.fingerprint }
    case 'SET_ROUND': return { ...state, roundId: action.roundId, roundPhase: action.phase }
    case 'ADD_ROUND_RESPONSE': return { ...state, roundResponses: [...state.roundResponses, action.response] }
    case 'SET_ROUND_PHASE': return { ...state, roundPhase: action.phase }
    case 'SET_COMPARISON_OUTCOME': return { ...state, comparisonOutcome: action.outcome }
    case 'SET_STEP': return { ...state, step: action.step }
    case 'SET_ERROR': return { ...state, error: action.error }
    case 'SET_LOADING': return { ...state, loading: action.loading }
  }
}

const initialState: DemoState = {
  step: 0,
  pool: null,
  agents: [],
  spec: DEFAULT_SPEC,
  fingerprintHex: '',  // computed async on mount
  roundId: null,
  roundPhase: null,
  roundResponses: [],
  comparisonOutcome: null,
  error: null,
  loading: null,
}

export default function PoolDemoPage() {
  const [state, dispatch] = useReducer(reducer, initialState)
  const { step, pool, agents, spec, fingerprintHex, roundId, roundPhase, comparisonOutcome, error, loading } = state

  // Compute initial fingerprint on mount
  useEffect(() => {
    computeFingerprint(DEFAULT_SPEC).then(fp =>
      dispatch({ type: 'SET_SPEC', spec: DEFAULT_SPEC, fingerprint: toHex(fp) })
    )
  }, [])

  // --- Section 1: Pool Setup ---
  async function handleCreatePool() {
    dispatch({ type: 'SET_ERROR', error: null })
    dispatch({ type: 'SET_LOADING', loading: 'Creating pool...' })
    try {
      const pool = await poolApi.createPool({
        name: 'Risk Analysis Pool',
        comparison_method: { method: 'exact' },
        compute_deadline_seconds: 300,
        min_principals: 2,
      })
      dispatch({ type: 'SET_POOL', pool })
      dispatch({ type: 'SET_STEP', step: 1 })
    } catch (e) {
      dispatch({ type: 'SET_ERROR', error: e instanceof Error ? e.message : String(e) })
    } finally {
      dispatch({ type: 'SET_LOADING', loading: null })
    }
  }

  // --- Section 2: Agent Registration ---
  async function handleRegisterAll() {
    if (!pool) return
    dispatch({ type: 'SET_ERROR', error: null })
    dispatch({ type: 'SET_LOADING', loading: 'Generating keypairs and registering agents...' })
    try {
      const newAgents: AgentState[] = []
      for (let i = 0; i < ORG_NAMES.length; i++) {
        const org = ORG_NAMES[i]
        const keypair = await generateKeyPair()
        const agentId = crypto.randomUUID()
        const publicKeyHex = toHex(keypair.publicKey)
        await poolApi.joinPool(pool.id, {
          agent_id: agentId,
          public_key: publicKeyHex,
          principal_id: org.principal,
        })
        newAgents.push({
          id: agentId,
          name: org.name,
          principal: org.principal,
          keypair,
          publicKeyHex,
          registered: true,
          role: i < 3 ? (i === 0 ? 'requester' : 'validator') : 'consumer',
          result: null, evidence: null, nonce: null,
          sealHash: null, sealSig: null, fingerprint: null, evidenceHash: null,
          revealed: false, cacheResult: null,
        })
      }
      dispatch({ type: 'SET_AGENTS', agents: newAgents })
      dispatch({ type: 'SET_STEP', step: 2 })
    } catch (e) {
      dispatch({ type: 'SET_ERROR', error: e instanceof Error ? e.message : String(e) })
    } finally {
      dispatch({ type: 'SET_LOADING', loading: null })
    }
  }

  // --- Section 3: Computation Spec ---
  async function handleSpecReady() {
    const fp = await computeFingerprint(spec)
    dispatch({ type: 'SET_SPEC', spec, fingerprint: toHex(fp) })
    dispatch({ type: 'SET_STEP', step: 3 })
  }

  // --- Section 4: Protocol Step-Through ---
  async function handleSubmitCompute(agentIndex: number) {
    if (!pool) return
    const agent = agents[agentIndex]
    if (!agent.keypair) return
    dispatch({ type: 'SET_ERROR', error: null })
    dispatch({ type: 'SET_LOADING', loading: `Agent ${agent.name} computing and sealing...` })
    try {
      const result = await simulatedCompute(spec)
      const evidence: ExecutionEvidence = {
        provider_request_id: `sim-${crypto.randomUUID().slice(0, 8)}`,
        model_echo: spec.model,
        token_counts: { input: 500, output: 200 },
        timestamps: { started: new Date().toISOString(), completed: new Date().toISOString() },
      }
      const seal = await createSealData(spec, agent.id, result, evidence, agent.keypair.secretKey)
      const sealHashHex = toHex(seal.sealHash)
      const sealSigHex = toHex(seal.sealSig)

      dispatch({
        type: 'UPDATE_AGENT', index: agentIndex, update: {
          result, evidence,
          nonce: seal.nonce,
          sealHash: sealHashHex,
          sealSig: sealSigHex,
          fingerprint: toHex(seal.fingerprint),
          evidenceHash: toHex(seal.evidenceHash),
        },
      })

      if (agentIndex === 0) {
        // Requester: submit compute
        const resp = await poolApi.submitCompute(pool.id, {
          agent_id: agent.id,
          computation_spec: spec,
          seal_hash: sealHashHex,
          seal_sig: sealSigHex,
        })
        dispatch({ type: 'SET_ROUND', roundId: resp.round_id, phase: resp.phase })
      } else {
        // Validator: submit seal
        if (!roundId) return
        const resp = await poolApi.submitSeal(pool.id, roundId, {
          agent_id: agent.id,
          seal_hash: sealHashHex,
          seal_sig: sealSigHex,
        })
        dispatch({ type: 'ADD_ROUND_RESPONSE', response: resp })
        dispatch({ type: 'SET_ROUND_PHASE', phase: resp.phase })
      }
    } catch (e) {
      dispatch({ type: 'SET_ERROR', error: e instanceof Error ? e.message : String(e) })
    } finally {
      dispatch({ type: 'SET_LOADING', loading: null })
    }
  }

  async function handleRevealAll() {
    if (!pool || !roundId) return
    dispatch({ type: 'SET_ERROR', error: null })
    dispatch({ type: 'SET_LOADING', loading: 'Revealing all values...' })
    try {
      let lastResp: RoundStatusResponse | null = null
      for (let i = 0; i < 3; i++) {
        const agent = agents[i]
        if (!agent.result || !agent.evidence || !agent.nonce) continue
        const resp = await poolApi.submitReveal(pool.id, roundId, {
          agent_id: agent.id,
          result: toHex(agent.result),
          evidence: agent.evidence,
          nonce: toHex(agent.nonce),
        })
        dispatch({ type: 'UPDATE_AGENT', index: i, update: { revealed: true } })
        dispatch({ type: 'ADD_ROUND_RESPONSE', response: resp })
        lastResp = resp
      }
      if (lastResp) {
        dispatch({ type: 'SET_ROUND_PHASE', phase: lastResp.phase })
        dispatch({ type: 'SET_COMPARISON_OUTCOME', outcome: lastResp.message })
      }
      dispatch({ type: 'SET_STEP', step: 4 })
    } catch (e) {
      dispatch({ type: 'SET_ERROR', error: e instanceof Error ? e.message : String(e) })
    } finally {
      dispatch({ type: 'SET_LOADING', loading: null })
    }
  }

  // --- Section 5: Cache Hits ---
  async function handleCacheQueries() {
    if (!pool) return
    dispatch({ type: 'SET_ERROR', error: null })
    dispatch({ type: 'SET_LOADING', loading: 'Querying cache for remaining agents...' })
    try {
      for (let i = 3; i < agents.length; i++) {
        const result = await poolApi.queryCache(pool.id, fingerprintHex)
        dispatch({ type: 'UPDATE_AGENT', index: i, update: { cacheResult: result } })
      }
      dispatch({ type: 'SET_STEP', step: 5 })
    } catch (e) {
      dispatch({ type: 'SET_ERROR', error: e instanceof Error ? e.message : String(e) })
    } finally {
      dispatch({ type: 'SET_LOADING', loading: null })
    }
  }

  // --- Seal verification helper (async) ---
  async function verifySealLocally(agentIndex: number): Promise<boolean> {
    const agent = agents[agentIndex]
    if (!agent.result || !agent.nonce || !agent.evidence || !agent.sealHash) return false
    const fp = await computeFingerprint(spec)
    const evidenceHash = await computeEvidenceHash(agent.evidence)
    const recomputed = await createSeal(fp, agent.id, agent.result, evidenceHash, agent.nonce)
    return toHex(recomputed) === agent.sealHash
  }

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-2">Common-Pool Computing Demo</h1>
      <p className="text-gray-600 mb-6">
        Interactive walkthrough of the cross-validation protocol. Each step drives the real backend API.
      </p>

      <PoolPhaseIndicator currentStep={step} />

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>
      )}
      {loading && (
        <div className="mb-4 p-3 bg-blue-50 border border-blue-200 rounded-lg text-sm text-blue-700">{loading}</div>
      )}

      {/* Section 1: Pool Setup */}
      <Section title="1. Pool Setup" done={step > 0}>
        {!pool ? (
          <div>
            <p className="text-sm text-gray-600 mb-3">
              Create a computing pool with exact comparison and a minimum of 2 independent principals.
            </p>
            <button onClick={handleCreatePool} disabled={!!loading} className="btn">
              Create Pool
            </button>
          </div>
        ) : (
          <div className="bg-green-50 border border-green-200 rounded-lg p-4">
            <div className="text-sm font-medium text-green-800 mb-2">Pool Created</div>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
              <dt className="text-gray-500">Pool ID</dt>
              <dd className="font-mono truncate">{pool.id}</dd>
              <dt className="text-gray-500">Name</dt>
              <dd>{pool.name}</dd>
              <dt className="text-gray-500">Comparison</dt>
              <dd>{pool.comparison_method.method}</dd>
              <dt className="text-gray-500">Min Principals</dt>
              <dd>{pool.min_principals}</dd>
            </dl>
          </div>
        )}
      </Section>

      {/* Section 2: Agent Registration */}
      {step >= 1 && (
        <Section title="2. Agent Registration" done={step > 1}>
          <p className="text-sm text-gray-600 mb-3">
            7 agents from different organizations. The first 3 will validate; the remaining 4 will consume cached results.
          </p>
          {agents.length === 0 ? (
            <button onClick={handleRegisterAll} disabled={!!loading} className="btn">
              Generate Keys &amp; Register All
            </button>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {agents.map((a) => (
                <AgentCard key={a.id} name={a.name} agentId={a.id} publicKey={a.publicKeyHex} role={a.role} />
              ))}
            </div>
          )}
        </Section>
      )}

      {/* Section 3: Computation Spec */}
      {step >= 2 && (
        <Section title="3. Computation Spec" done={step > 2}>
          <p className="text-sm text-gray-600 mb-3">
            The spec fully determines what to compute. Its SHA-256 fingerprint is the cache key &mdash; same spec always produces the same fingerprint.
          </p>
          <SpecEditor spec={spec} onFingerprint={(fp) =>
            dispatch({ type: 'SET_SPEC', spec, fingerprint: fp })
          } onChange={(s) => dispatch({ type: 'SET_SPEC', spec: s, fingerprint: fingerprintHex })} />
          <div className="mt-3 p-3 bg-gray-50 rounded-lg">
            <div className="text-xs text-gray-500 mb-1">Fingerprint (SHA-256)</div>
            <div className="text-xs font-mono break-all">{fingerprintHex || 'computing...'}</div>
          </div>
          {step === 2 && (
            <button onClick={handleSpecReady} disabled={!!loading} className="btn mt-3">
              Continue with this spec
            </button>
          )}
        </Section>
      )}

      {/* Section 4: Protocol Step-Through */}
      {step >= 3 && (
        <Section title="4. Seal & Reveal Protocol" done={step > 3}>
          <p className="text-sm text-gray-600 mb-4">
            Each agent computes the result, creates a cryptographic seal, and submits it.
            After all seals are in, everyone reveals their values for comparison.
          </p>

          {/* 4a-4c: Submit seals for agents 0-2 */}
          {[0, 1, 2].map((i) => {
            const agent = agents[i]
            if (!agent) return null
            const isFirst = i === 0
            const prevDone = i === 0 ? true : !!agents[i - 1]?.sealHash
            const label = isFirst ? 'Submit Computation (Requester)' : `Submit Seal (Validator ${i})`
            return (
              <div key={agent.id} className="mb-4">
                <div className="flex items-center gap-3 mb-2">
                  <AgentCard name={agent.name} agentId={agent.id} publicKey={agent.publicKeyHex} role={agent.role} highlight={!!agent.sealHash} />
                </div>
                {!agent.sealHash && prevDone && step === 3 && (
                  <button onClick={() => handleSubmitCompute(i)} disabled={!!loading} className="btn text-sm">
                    {label}
                  </button>
                )}
                {agent.sealHash && (
                  <SealDetail agent={agent} onVerify={() => verifySealLocally(i)} />
                )}
              </div>
            )
          })}

          {/* 4d: Reveal all */}
          {agents[2]?.sealHash && !agents[0]?.revealed && step === 3 && (
            <button onClick={handleRevealAll} disabled={!!loading} className="btn mt-2">
              Reveal All &amp; Compare
            </button>
          )}

          {/* Show comparison outcome */}
          {comparisonOutcome && (
            <div className="mt-4 p-4 bg-green-50 border border-green-200 rounded-lg">
              <div className="text-sm font-medium text-green-800">Validation Complete</div>
              <div className="text-sm text-green-700 mt-1">{comparisonOutcome}</div>
              <div className="text-xs text-gray-500 mt-1">Round phase: {roundPhase}</div>
            </div>
          )}
        </Section>
      )}

      {/* Section 5: Cache Hits */}
      {step >= 4 && (
        <Section title="5. Cache Hits" done={step > 4}>
          <p className="text-sm text-gray-600 mb-3">
            The remaining {agents.length - 3} agents query the cache. Instant results, zero compute cost.
          </p>
          {!agents[3]?.cacheResult && (
            <button onClick={handleCacheQueries} disabled={!!loading} className="btn">
              Query Cache for Remaining Agents
            </button>
          )}
          {agents.slice(3).some(a => a.cacheResult) && (
            <div className="space-y-2 mt-3">
              {agents.slice(3).map((a) => (
                <div key={a.id} className="flex items-center gap-3 p-3 bg-green-50 border border-green-200 rounded-lg">
                  <div className="flex-1">
                    <div className="text-sm font-medium text-gray-900">{a.name}</div>
                    <div className="text-xs text-gray-500">
                      Cost: {formatUsd(0)} &middot; Latency: &lt;10ms
                    </div>
                  </div>
                  {a.cacheResult && (
                    <div className="text-xs">
                      <span className="text-green-700 font-medium">Cache Hit</span>
                      <div className="text-gray-500 font-mono truncate max-w-48" title={a.cacheResult.result}>
                        {a.cacheResult.result.slice(0, 24)}...
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </Section>
      )}

      {/* Section 6: Cost Dashboard */}
      {step >= 5 && (
        <Section title="6. Cost Savings" done={false}>
          <CostComparisonCard
            model={spec.model}
            validatorCount={3}
            cacheHitCount={agents.length - 3}
          />
        </Section>
      )}
    </div>
  )
}

// --- Sub-components ---

function Section({ title, done, children }: { title: string; done: boolean; children: React.ReactNode }) {
  return (
    <div className={`mb-8 p-6 rounded-lg border ${done ? 'border-gray-200 bg-white' : 'border-indigo-200 bg-white'}`}>
      <h2 className="text-lg font-semibold text-gray-900 mb-3 flex items-center gap-2">
        {title}
        {done && <span className="text-green-600 text-sm font-normal">(complete)</span>}
      </h2>
      {children}
    </div>
  )
}

function SpecEditor({ spec, onChange, onFingerprint }: {
  spec: ComputationSpec
  onChange: (s: ComputationSpec) => void
  onFingerprint: (fp: string) => void
}) {
  function update(s: ComputationSpec) {
    onChange(s)
    computeFingerprint(s).then(fp => onFingerprint(toHex(fp)))
  }

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-xs text-gray-500 block mb-1">Provider</label>
          <input className="input w-full text-sm" value={spec.provider}
            onChange={(e) => update({ ...spec, provider: e.target.value })} />
        </div>
        <div>
          <label className="text-xs text-gray-500 block mb-1">Model</label>
          <input className="input w-full text-sm" value={spec.model}
            onChange={(e) => update({ ...spec, model: e.target.value })} />
        </div>
        <div>
          <label className="text-xs text-gray-500 block mb-1">Temperature</label>
          <input className="input w-full text-sm" type="number" step="0.1" value={spec.temperature}
            onChange={(e) => update({ ...spec, temperature: parseFloat(e.target.value) || 0 })} />
        </div>
        <div>
          <label className="text-xs text-gray-500 block mb-1">Seed</label>
          <input className="input w-full text-sm" type="number" value={spec.seed ?? ''}
            onChange={(e) => update({ ...spec, seed: e.target.value ? parseInt(e.target.value) : undefined })} />
        </div>
      </div>
      <div>
        <label className="text-xs text-gray-500 block mb-1">System Prompt</label>
        <textarea className="input w-full text-sm" rows={2} value={spec.system_prompt}
          onChange={(e) => update({ ...spec, system_prompt: e.target.value })} />
      </div>
      <div>
        <label className="text-xs text-gray-500 block mb-1">User Prompt</label>
        <textarea className="input w-full text-sm" rows={3} value={spec.user_prompt}
          onChange={(e) => update({ ...spec, user_prompt: e.target.value })} />
      </div>
    </div>
  )
}

function SealDetail({ agent, onVerify }: { agent: AgentState; onVerify: () => Promise<boolean> }) {
  const [verified, setVerified] = useState<boolean | null>(null)
  if (!agent.sealHash) return null

  return (
    <CryptoDetailPanel
      title={`Seal Details - ${agent.name}`}
      fields={[
        { label: 'Agent ID', value: agent.id },
        { label: 'Fingerprint', value: agent.fingerprint ?? '' },
        { label: 'Result (hex)', value: agent.result ? toHex(agent.result) : '' },
        { label: 'Evidence Hash', value: agent.evidenceHash ?? '' },
        { label: 'Nonce', value: agent.nonce ? toHex(agent.nonce) : '' },
        { label: 'Seal Hash = SHA-256(fp || agent_id || result || evidence_hash || nonce)', value: agent.sealHash },
        { label: 'Seal Signature (Ed25519)', value: agent.sealSig ?? '' },
      ]}
      onVerify={() => { onVerify().then(ok => setVerified(ok)) }}
      verifyLabel="Recompute seal locally"
      verified={verified}
    />
  )
}
