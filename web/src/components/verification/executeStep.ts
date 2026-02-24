/**
 * Execute verification code strings via AsyncFunction.
 *
 * The utility functions (hexToBytes, sha256, etc.) are compiled once from
 * UTILITY_CODE and passed as named parameters to each step's code string.
 * This is why the step code can reference them by name — they're in scope.
 */

import { UTILITY_CODE, UTILITY_NAMES } from './codeStrings'

export interface StepOutput {
  status: 'pass' | 'fail' | 'error'
  summary: string
  details?: Array<{ label: string; value: string; match?: boolean }>
  data?: unknown
}

// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor as new (
  ...args: string[]
) => (...args: unknown[]) => Promise<unknown>

// Compiled utility functions, cached after first use
// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
let utilityFns: Record<string, Function> | null = null

// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
function getUtilities(): Record<string, Function> {
  if (utilityFns) return utilityFns
  const fn = new Function(
    UTILITY_CODE + '\nreturn { ' + UTILITY_NAMES.join(', ') + ' };',
  // eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
  ) as () => Record<string, Function>
  utilityFns = fn()
  return utilityFns
}

/**
 * Execute a verification code string. The utility functions are provided
 * as named parameters so the code can reference them directly.
 */
export async function executeStep(code: string): Promise<StepOutput> {
  const utils = getUtilities()
  const names = Object.keys(utils)
  const values = Object.values(utils)
  try {
    const fn = new AsyncFunction(...names, code)
    const result = await fn(...values)
    return result as StepOutput
  } catch (err) {
    return {
      status: 'error',
      summary: String(err instanceof Error ? err.message : err),
    }
  }
}
