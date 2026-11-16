import assert from 'node:assert/strict'
import { test } from 'node:test'
import { LinkSupervisor } from '../src/index.ts'

const sleep = (ms: number): Promise<void> => new Promise(resolve => setTimeout(resolve, ms))

const gapsOf = (starts: number[]): number[] => starts.slice(1).map((at, index) => at - starts[index]!)

test('a link that drops at once backs off, doubles, and stops at the ceiling', async () => {
  const starts: number[] = []
  const supervisor = new LinkSupervisor({
    retry: { minMs: 20, maxMs: 160, factor: 2, jitter: 0, stableMs: 10_000 },
    attempt: async ({ closed }) => { starts.push(Date.now()); setTimeout(() => closed(), 0) },
  })
  supervisor.start()
  await sleep(700)
  await supervisor.stop()
  const gaps = gapsOf(starts)
  assert.ok(gaps.length >= 5, `kept retrying, attempts: ${starts.length}`)
  assert.ok(gaps[0]! >= 15 && gaps[0]! <= 45, `first wait near the minimum: ${gaps.join(',')}`)
  assert.ok(gaps[1]! >= 30 && gaps[1]! <= 65, `second wait doubled: ${gaps.join(',')}`)
  assert.ok(gaps[2]! >= 60 && gaps[2]! <= 110, `third wait doubled: ${gaps.join(',')}`)
  for (const gap of gaps.slice(3)) assert.ok(gap <= 200, `the ceiling holds: ${gaps.join(',')}`)
  assert.deepEqual(supervisor.status, 'stopped')
})

test('each wait is spread around its base, never below it by more than the jitter', async () => {
  const starts: number[] = []
  const supervisor = new LinkSupervisor({
    retry: { minMs: 40, maxMs: 10_000, factor: 2, jitter: 0.2, stableMs: 10_000 },
    attempt: async ({ closed }) => { starts.push(Date.now()); setTimeout(() => closed(), 0) },
  })
  supervisor.start()
  await sleep(500)
  await supervisor.stop()
  const gaps = gapsOf(starts)
  const bases = [40, 80, 160, 320]
  for (const [index, gap] of gaps.entries()) {
    const base = bases[Math.min(index, bases.length - 1)]!
    assert.ok(gap >= base * 0.7 && gap <= base * 1.4, `wait ${index} near ${base} ms: ${gaps.join(',')}`)
  }
})

test('a link that stays up resets the wait', async () => {
  const starts: number[] = []
  const supervisor = new LinkSupervisor({
    retry: { minMs: 20, maxMs: 5_000, factor: 4, jitter: 0, stableMs: 15 },
    attempt: async ({ closed }) => { starts.push(Date.now()); setTimeout(() => closed(), 25) },
  })
  supervisor.start()
  await sleep(400)
  await supervisor.stop()
  const gaps = gapsOf(starts)
  assert.ok(gaps.length >= 3, `kept reconnecting: ${starts.length}`)
  for (const gap of gaps) assert.ok(gap <= 120, `a stable link keeps the wait at the minimum: ${gaps.join(',')}`)
})

test('only one attempt runs at a time', async () => {
  let attempts = 0
  const supervisor = new LinkSupervisor({
    attempt: async () => { attempts += 1 },
  })
  supervisor.start()
  supervisor.start()
  supervisor.start()
  await sleep(60)
  assert.equal(attempts, 1)
  assert.equal(supervisor.attemptCount, 1)
  assert.equal(supervisor.status, 'online')
  await supervisor.stop()
  assert.equal(supervisor.status, 'stopped')
})

test('a failed attempt reports the error and is retried', async () => {
  const errors: string[] = []
  let attempts = 0
  const supervisor = new LinkSupervisor({
    retry: { minMs: 20, maxMs: 40, jitter: 0 },
    onError: (error, attempt) => errors.push(`${attempt}:${error.message}`),
    attempt: async () => { attempts += 1; throw Object.assign(new Error('HOST_OFFLINE'), { code: 'HOST_OFFLINE' }) },
  })
  supervisor.start()
  await sleep(150)
  await supervisor.stop()
  assert.ok(attempts >= 3, `retried: ${attempts}`)
  assert.ok(errors.length === attempts)
  assert.ok(errors[0]!.endsWith('HOST_OFFLINE'))
})

test('reconnect() leaves the wait and tries at once', async () => {
  const starts: number[] = []
  const supervisor = new LinkSupervisor({
    retry: { minMs: 1_000, maxMs: 1_000, jitter: 0 },
    attempt: async ({ closed }) => { starts.push(Date.now()); setTimeout(() => closed(), 0) },
  })
  supervisor.start()
  await sleep(40)
  assert.equal(starts.length, 1)
  supervisor.reconnect()
  await sleep(40)
  assert.equal(starts.length, 2, 'the wait was cut short')
  await supervisor.stop()
})

test('stop() aborts an attempt that is still connecting', async () => {
  let aborted = false
  let started = false
  const supervisor = new LinkSupervisor({
    attempt: async ({ signal }) => {
      started = true
      await new Promise<void>(resolve => signal.addEventListener('abort', () => { aborted = true; resolve() }, { once: true }))
    },
  })
  supervisor.start()
  await sleep(30)
  assert.equal(started, true)
  await supervisor.stop()
  assert.equal(aborted, true)
  assert.equal(supervisor.status, 'stopped')
})

test('an invalid retry policy is refused', () => {
  assert.throws(() => new LinkSupervisor({ attempt: async () => {}, retry: { minMs: 0 } }), /retry policy/)
  assert.throws(() => new LinkSupervisor({ attempt: async () => {}, retry: { minMs: 100, maxMs: 10 } }), /retry policy/)
})
