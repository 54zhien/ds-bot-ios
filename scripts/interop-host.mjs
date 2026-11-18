#!/usr/bin/env node
// A minimal DS Bot host for the CI interop test.
//
// It registers one pairing code with the relay that is already running, waits until the
// relay answers, then writes the endpoint the Swift test needs as Swift source and stays
// alive until the workflow kills it.
//
// The Swift source is the only channel that works: xcodebuild does not hand the shell's
// environment variables to the test process, so the values have to be compiled in.
//
// Environment:
//   PORT                        relay port, default 8787
//   INTEROP_HOST                relay host, default 127.0.0.1
//   INTEROP_CONFIG_PATH         where to write the Swift file
//   INTEROP_ONLINE_TIMEOUT_MS   how long to wait for the relay, default 60000

import { createHash } from 'node:crypto'
import { mkdir, rename, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import {
  DeviceRegistry,
  HostLink,
  LINK_PATH,
  deviceIdFor,
  generateKeyPair,
  randomToken,
} from '../link/src/index.ts'

const port = Number(process.env.PORT ?? 8787)
const relayHost = process.env.INTEROP_HOST ?? '127.0.0.1'
const outFile = resolve(process.env.INTEROP_CONFIG_PATH ?? 'native/Tests/InteropTests/InteropConfig.generated.swift')
const onlineTimeoutMs = Number(process.env.INTEROP_ONLINE_TIMEOUT_MS ?? 60000)

// A pairing code lives five minutes by default, which is shorter than a cold xcodebuild.
const PAIRING_TTL_MS = 30 * 60 * 1000

// A real state reply lists every Bot with its instructions, so it is far past the 48 KiB
// fragment size. The fixture has to be just as large, or the phone's fragment path never
// runs here and a phone that cannot reassemble one still looks healthy.
const FIXTURE_BOTS = 40
const FIXTURE_BOT_TEXT_BYTES = 3000

// The values are a URL, a device id, a base64url key and a short code: anything else in
// them means something upstream is wrong, and a stray quote would produce broken Swift.
const SAFE = new RegExp('^[A-Za-z0-9._:/-]+$')

function safe(name, value) {
  const text = String(value)
  if (!SAFE.test(text)) throw new Error(name + ' holds characters that cannot go into the Swift file: ' + text)
  return text
}

// Every Bot names its own index at the start and the end of its text, so a reply whose
// fragments were joined in the wrong order cannot pass by coincidence.
function botText(index) {
  const line = 'Bot ' + index + ' carries this text to keep the state reply above one fragment. '
  let text = line
  while (text.length < FIXTURE_BOT_TEXT_BYTES) text += line
  return text + 'end of bot ' + index
}

function fixtureState() {
  const bots = Array.from({ length: FIXTURE_BOTS }, (_, index) => ({
    id: 'bot-' + String(index).padStart(2, '0'),
    name: 'Fixture Bot ' + index,
    role: 'crew',
    color: 'blue',
    model: 'deepseek/deepseek-chat',
    effort: 'high',
    sessionId: 'fixture-session-' + index,
    parts: [],
    instructions: botText(index),
  }))
  return {
    revision: 7,
    liveKey: 'fixture-live',
    bots,
    rooms: [],
    work: { bots: {}, rooms: {}, approvals: [], waiting: {}, turns: {}, steered: {} },
    prefs: {},
  }
}

const url = 'ws://' + relayHost + ':' + port + LINK_PATH
const keys = generateKeyPair()
const identity = { deviceId: deviceIdFor(keys.publicKey), ...keys }
const registry = new DeviceRegistry()
const pairing = registry.openPairing(PAIRING_TTL_MS)

let calls = 0
const link = new HostLink({
  url,
  identity,
  accessToken: randomToken(),
  name: 'CI Desk',
  admits: (deviceId, identityKey) => registry.admits(deviceId, identityKey),
  authorize: (deviceId, identityKey, hello) => registry.authorize(deviceId, identityKey, hello),
  handle: async (method, params) => {
    calls += 1
    console.log('interop host: rpc ' + method + ' (call ' + calls + ')')
    // The phone asks for state as bot/state, the way the app does, not as one method name.
    if (method === 'bot' && params !== null && typeof params === 'object' && params.endpoint === 'state') {
      const state = fixtureState()
      const reply = { ok: true, value: state }
      console.log('interop host: state reply ' + Buffer.byteLength(JSON.stringify(reply), 'utf8')
        + ' bytes, ' + state.bots.length + ' bots')
      return reply
    }
    // The other direction: the phone sends one oversized request and gets back what the
    // host measured, which proves the fragments arrived whole and in order.
    if (method === 'interop.echo') {
      const text = params !== null && typeof params === 'object' && typeof params.text === 'string' ? params.text : ''
      return {
        ok: true,
        bytes: Buffer.byteLength(text, 'utf8'),
        sha256: createHash('sha256').update(text, 'utf8').digest('hex'),
        head: text.slice(0, 16),
        tail: text.slice(-16),
      }
    }
    return { ok: true, method, params }
  },
  onStatus: (status) => console.log('interop host: status ' + status),
  retryMs: [100, 500],
})

function swiftSource() {
  return [
    '// Generated by scripts/interop-host.mjs for one CI run; do not commit, do not edit.',
    '// xcodebuild does not pass environment variables to the test process, so these',
    '// values are compiled in instead of read at runtime.',
    'enum InteropConfig {',
    '    static let serverURL = "' + safe('serverURL', url) + '"',
    '    static let hostDeviceId = "' + safe('hostDeviceId', identity.deviceId) + '"',
    '    static let hostPublicKey = "' + safe('hostPublicKey', identity.publicKey) + '"',
    '    static let pairingCode = "' + safe('pairingCode', pairing.code) + '"',
    '}',
    '',
  ].join('\n')
}

async function writeConfig() {
  await mkdir(dirname(outFile), { recursive: true })
  const temporary = outFile + '.tmp'
  await writeFile(temporary, swiftSource(), 'utf8')
  // Rename last: a half-written file must never be visible to xcodegen or the compiler.
  await rename(temporary, outFile)
  console.log('interop host: config written to ' + outFile)
}

let stopping = false
async function stop(signal) {
  if (stopping) return
  stopping = true
  console.log('interop host: ' + signal + ', stopping after ' + calls + ' call(s)')
  try { await link.stop() } catch (error) { console.log('interop host: stop failed: ' + String(error)) }
  process.exit(0)
}
process.once('SIGTERM', () => { void stop('SIGTERM') })
process.once('SIGINT', () => { void stop('SIGINT') })

console.log('interop host: relay ' + url)
console.log('interop host: device ' + identity.deviceId)

link.start()
try {
  await link.waitOnline(onlineTimeoutMs)
} catch (error) {
  console.log('interop host: the relay never answered: ' + String(error))
  process.exit(1)
}

await writeConfig()
console.log('interop host: online and paired-open, waiting for the phone')

// Keep the process alive; the workflow owns its lifetime.
await new Promise(() => {})
