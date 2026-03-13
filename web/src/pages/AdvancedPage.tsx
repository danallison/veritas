import { Link } from 'react-router-dom'

export default function AdvancedPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Advanced</h1>
        <p className="text-gray-600 mt-1">Ceremony protocol tools and low-level utilities.</p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Link
          to="/advanced/ceremonies/new"
          className="block p-5 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 hover:shadow-sm transition-all"
        >
          <h2 className="font-semibold text-gray-900">Create Ceremony</h2>
          <p className="text-sm text-gray-500 mt-1">Set up a cryptographic ceremony with commit-reveal.</p>
        </Link>
        <Link
          to="/advanced/random"
          className="block p-5 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 hover:shadow-sm transition-all"
        >
          <h2 className="font-semibold text-gray-900">Random Tools</h2>
          <p className="text-sm text-gray-500 mt-1">Coin flips, integer ranges, and UUIDs.</p>
        </Link>
        <Link
          to="/advanced/guide"
          className="block p-5 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 hover:shadow-sm transition-all"
        >
          <h2 className="font-semibold text-gray-900">Verification Guide</h2>
          <p className="text-sm text-gray-500 mt-1">Step-by-step guide to independently verify ceremony outcomes.</p>
        </Link>
        <Link
          to="/advanced/demo"
          className="block p-5 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 hover:shadow-sm transition-all"
        >
          <h2 className="font-semibold text-gray-900">Pool Demo</h2>
          <p className="text-sm text-gray-500 mt-1">Interactive demo of the common-pool computing protocol.</p>
        </Link>
      </div>
    </div>
  )
}
