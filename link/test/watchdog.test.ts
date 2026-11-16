import assert from 'node:assert/strict'
import { test } from 'node:test'
import { PROTOCOL_VERSION, RelayTransport, createControlFrame } from '../src/index.ts'

const sleep = (ms: number): Promise<void> => new Promise(resolve => setTimeout(resolve, ms))

class FakeSocket {
  readyState = 0
  sent: string[] = []
  binaryType = ''
  onopen?: () => void
  onmessage?: (event: { data: unknown }) => void
  onerror?: () => void
  onclose?: () => void
  send(data: unknown) { this.sent.push(String(data)) }
  close() { this.readyState = 3 }
}

interface WatchdogOptions {
  heartbeatIntervalMs?: number
  watchdogIntervalMs?: number
  watchdogSilenceMs?: number
  probeTimeoutMs?: number
  probeAttempts?: number
}

/** A transport the way the real handshake leaves it: ready, with the Server's hello.ack heard. */
async function ready(options: WatchdogOptions = {}) {
  const sockets: FakeSocket[] = []
  const transport = new RelayTransport('ws://unused', {
    deviceId: 'd-phone', identityKey: 'k', accessToken: 't', targetDeviceId: 'd-host',
    ...options,
    createSocket: () => { const socket = new FakeSocket(); sockets.push(socket); return socket as unknown as WebSocket },
  })
  const connecting = transport.connect()
  const socket = sockets[0]!
  socket.readyState = 1
  socket.onopen?.()
  const ack: Record<string, unknown> = {
    protocol: PROTOCOL_VERSION,
    serverVersion: 'test',
    connectionSessionId: 'session-1',
    maxControlFrameBytes: 64 * 1024,
    maxRelayFrameBytes: 1024 * 1024,
    capabilities: ['transport.relay'],
  }
  if (options.heartbeatIntervalMs !== undefined) ack.heartbeatIntervalMs = options.heartbeatIntervalMs
  const feed = (type: string, payload: unknown): void => socket.onmessage?.({ data: JSON.stringify(createControlFrame(type as never, payload)) })
  feed('hello.ack', ack)
  feed('connect.accepted', { connectionId: 'c-1' })
  await connecting
  return { transport, socket, feed }
}

const pings = (socket: FakeSocket): number => socket.sent
  .map(text => JSON.parse(text) as { type: string })
  .filter(frame => frame.type === 'ping').length

test('probe() works again once a frame answers it', async () => {
  const { transport, socket, feed } = await ready({ watchdogIntervalMs: 3_600_000, watchdogSilenceMs: 3_600_000, probeTimeoutMs: 3_600_000 })
  transport.probe()
  assert.equal(pings(socket), 1)
  transport.probe()
  assert.equal(pings(socket), 1, 'one probe at a time')
  feed('pong', { nonce: 1 })
  transport.probe()
  assert.equal(pings(socket), 2, 'an answered probe arms the next one')
  void transport.close()
})

test('one lost pong is retried, not fatal', async () => {
  const { transport, socket, feed } = await ready({ watchdogIntervalMs: 10, watchdogSilenceMs: 30, probeTimeoutMs: 80 })
  let closes = 0
  transport.onClose(() => { closes += 1 })
  await sleep(70)
  assert.equal(pings(socket), 1, 'a probe goes out after the silence window')
  await sleep(120)
  assert.equal(pings(socket), 2, 'the unanswered probe is sent again')
  assert.equal(closes, 0, 'one lost answer does not end the link')
  feed('pong', { nonce: 2 })
  await sleep(60)
  assert.equal(closes, 0)
  void transport.close()
})

test('two unanswered probes end the link', async () => {
  const { transport, socket } = await ready({ watchdogIntervalMs: 10, watchdogSilenceMs: 30, probeTimeoutMs: 40 })
  const closed = new Promise<Error | undefined>(resolve => transport.onClose(() => resolve(transport.closeReason)))
  const reason = await Promise.race([closed, sleep(1_000).then(() => undefined)])
  assert.ok(reason instanceof Error, 'the link reports its close')
  assert.equal((reason as Error & { code?: string }).code, 'SERVER_UNREACHABLE')
  assert.equal(pings(socket), 2, 'both probes went out before giving up')
  assert.equal(socket.readyState, 3)
})

test('one probe ends the link when the policy allows a single try', async () => {
  const { transport, socket } = await ready({ watchdogIntervalMs: 10, watchdogSilenceMs: 30, probeTimeoutMs: 40, probeAttempts: 1 })
  const closed = new Promise<Error | undefined>(resolve => transport.onClose(() => resolve(transport.closeReason)))
  const reason = await Promise.race([closed, sleep(1_000).then(() => undefined)])
  assert.ok(reason instanceof Error)
  assert.equal(pings(socket), 1)
})

test('the interval the Server states sets when the link is probed', async () => {
  const { transport, socket } = await ready({ heartbeatIntervalMs: 1_000, watchdogIntervalMs: 20 })
  await sleep(600)
  assert.equal(pings(socket), 0, 'silence below the Server interval is not probed')
  await sleep(700)
  assert.equal(pings(socket), 1, 'the probe follows the interval the Server stated')
  void transport.close()
})

test('an explicit silence threshold wins over the Server interval', async () => {
  const { transport, socket } = await ready({ heartbeatIntervalMs: 60_000, watchdogIntervalMs: 10, watchdogSilenceMs: 40 })
  await sleep(120)
  assert.ok(pings(socket) >= 1, 'the configured threshold is used, not the Server one')
  void transport.close()
})
