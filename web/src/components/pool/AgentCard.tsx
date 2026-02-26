// Agent display card showing organization, truncated key, and role.

interface Props {
  name: string
  agentId: string
  publicKey: string  // hex
  role: 'requester' | 'validator' | 'consumer'
  highlight?: boolean
}

const ROLE_COLORS = {
  requester: 'bg-blue-100 text-blue-800',
  validator: 'bg-purple-100 text-purple-800',
  consumer: 'bg-green-100 text-green-800',
}

export default function AgentCard({ name, agentId, publicKey, role, highlight }: Props) {
  return (
    <div className={`flex items-center gap-3 p-3 rounded-lg border ${highlight ? 'border-indigo-300 bg-indigo-50' : 'border-gray-200 bg-white'}`}>
      <div className="flex-1 min-w-0">
        <div className="font-medium text-sm text-gray-900">{name}</div>
        <div className="text-xs text-gray-500 font-mono truncate" title={agentId}>
          {agentId.slice(0, 8)}...
        </div>
        <div className="text-xs text-gray-400 font-mono truncate" title={publicKey}>
          pk: {publicKey.slice(0, 16)}...
        </div>
      </div>
      <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${ROLE_COLORS[role]}`}>
        {role}
      </span>
    </div>
  )
}
