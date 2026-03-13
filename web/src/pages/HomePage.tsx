import { Link } from 'react-router-dom'

export default function HomePage() {
  return (
    <div className="space-y-8">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Veritas</h1>
        <p className="text-gray-600">Verified AI output through independent cross-validation</p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Link
          to="/verify/new"
          className="block p-5 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors text-center"
        >
          <h2 className="text-lg font-semibold">Verify Output</h2>
          <p className="text-indigo-200 text-sm mt-1">Submit AI output for cross-validation</p>
        </Link>
        <Link
          to="/pools"
          className="block p-5 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 hover:shadow-sm transition-all text-center"
        >
          <h2 className="text-lg font-semibold text-gray-900">Pools</h2>
          <p className="text-gray-500 text-sm mt-1">Browse and manage volunteer pools</p>
        </Link>
        <Link
          to="/cache"
          className="block p-5 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 hover:shadow-sm transition-all text-center"
        >
          <h2 className="text-lg font-semibold text-gray-900">Cache</h2>
          <p className="text-gray-500 text-sm mt-1">Browse verified results</p>
        </Link>
      </div>

      <div className="border-t border-gray-200 pt-6">
        <h3 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">How it works</h3>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 text-sm">
          <div className="space-y-1">
            <p className="font-medium text-gray-900">1. Submit</p>
            <p className="text-gray-600">Post AI output to a volunteer pool for independent verification.</p>
          </div>
          <div className="space-y-1">
            <p className="font-medium text-gray-900">2. Validate</p>
            <p className="text-gray-600">Randomly selected agents reproduce the computation independently.</p>
          </div>
          <div className="space-y-1">
            <p className="font-medium text-gray-900">3. Verify</p>
            <p className="text-gray-600">Results compared for agreement. Unanimous or majority = verified.</p>
          </div>
        </div>
      </div>

      <div className="border-t border-gray-200 pt-6">
        <h3 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Advanced</h3>
        <div className="flex gap-3">
          <Link
            to="/advanced/ceremonies/new"
            className="text-sm text-gray-600 hover:text-gray-900 px-3 py-1.5 border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
          >
            Create Ceremony
          </Link>
          <Link
            to="/advanced/random"
            className="text-sm text-gray-600 hover:text-gray-900 px-3 py-1.5 border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
          >
            Random Tools
          </Link>
          <Link
            to="/advanced/guide"
            className="text-sm text-gray-600 hover:text-gray-900 px-3 py-1.5 border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
          >
            Verification Guide
          </Link>
        </div>
      </div>
    </div>
  )
}
