import type { RpcClient } from '../../../link/src/index.ts'
import type { TeamState } from '../connection.ts'

// Pure RPC wrappers: no react-native here on purpose. node --test loads this file
// through type stripping, which cannot resolve a bare react-native import.

type BotResult<T> = { ok: true; value: T } | { ok: false; error: { code: string; message: string } }

/** Calls one DS Bot endpoint on the computer, the same one its window calls. */
export async function callBot<T>(client: RpcClient, endpoint: string, payload: unknown = {}, signal?: AbortSignal): Promise<T> {
  const result = await client.rpc<BotResult<T>>('bot', { endpoint, payload }, { signal })
  if (!result.ok) throw Object.assign(new Error(result.error.message), { code: result.error.code })
  return result.value
}

/**
 * Same call, but the request carries `state` (the payload the `state` endpoint
 * would take). A write that moved the team answers with the new state in the
 * same reply, so the phone needs no second round trip.
 */
export async function callBotState<T>(client: RpcClient, endpoint: string, payload: unknown, state: unknown, signal?: AbortSignal): Promise<{ value: T; state?: TeamState }> {
  const result = await client.rpc<BotResult<T> & { state?: TeamState }>('bot', { endpoint, payload, state }, { signal })
  if (!result.ok) throw Object.assign(new Error(result.error.message), { code: result.error.code })
  return { value: result.value, state: result.state }
}
