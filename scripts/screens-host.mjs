#!/usr/bin/env node
// A structure-faithful host for the CI screenshot run.
//
// It answers the same endpoints the desktop host answers (hello, notices, state, chat,
// room-chat, image) with the same envelope the phone expects: {ok:true, value:{...}}.
// The data is a fixture, so the screenshots show a filled chat without a real computer.
//
// It also writes the pairing payload the app reads at launch, so the run needs no QR
// code: screens/pairing.json (for reading) and screens/pairing.plist (for defaults import).
//
// Environment:
//   PORT            relay port, default 8787
//   INTEROP_HOST    relay host, default 127.0.0.1
//   SCREENS_OUT     where to write the pairing files, default screens
//   SCREENS_HOST_TIMEOUT_MS  how long to wait for the relay, default 60000

import { mkdir, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { deflateSync } from 'node:zlib'
import { HostLink, LINK_PATH, deviceIdFor, generateKeyPair, randomToken } from '../link/src/index.ts'

const port = Number(process.env.PORT ?? 8787)
const relayHost = process.env.INTEROP_HOST ?? '127.0.0.1'
const outDir = resolve(process.env.SCREENS_OUT ?? 'screens')
const onlineTimeoutMs = Number(process.env.SCREENS_HOST_TIMEOUT_MS ?? 60000)
const url = 'ws://' + relayHost + ':' + port + LINK_PATH

// ---------------------------------------------------------------- image

function crc32(buffer) {
  let table = crc32.table
  if (!table) {
    table = crc32.table = new Int32Array(256)
    for (let n = 0; n < 256; n += 1) {
      let c = n
      for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
      table[n] = c
    }
  }
  let crc = -1
  for (const byte of buffer) crc = (crc >>> 8) ^ table[(crc ^ byte) & 0xff]
  return (crc ^ -1) >>> 0
}

function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data])
  const length = Buffer.alloc(4)
  length.writeUInt32BE(data.length)
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(body))
  return Buffer.concat([length, body, crc])
}

// A small gradient so the image row of the chat looks like a real screenshot.
function gradientPng(width, height) {
  const raw = Buffer.alloc((width * 3 + 1) * height)
  for (let y = 0; y < height; y += 1) {
    const row = y * (width * 3 + 1)
    raw[row] = 0
    for (let x = 0; x < width; x += 1) {
      const at = row + 1 + x * 3
      raw[at] = 28 + Math.round((x / width) * 180)
      raw[at + 1] = 60 + Math.round((y / height) * 120)
      raw[at + 2] = 160 - Math.round((x / width) * 90)
    }
  }
  const header = Buffer.alloc(13)
  header.writeUInt32BE(width, 0)
  header.writeUInt32BE(height, 4)
  header[8] = 8
  header[9] = 2
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

const image = gradientPng(480, 270).toString('base64')

// ---------------------------------------------------------------- fixture

const T = 1762000000000
let seq = 0
const nextSeq = () => { seq += 1; return seq }

const bots = [
  {
    id: 'b-chief', name: 'Chief', role: 'Main Bot', color: 'deepseek', avatar: { shape: 'whale' },
    model: 'deepseek-official/deepseek-v4.1', effort: 'medium', workDir: '~/ds-bot',
    instructions: 'Keep the team moving and review every diff before it lands.',
    sessionId: 's-chief', capabilities: ['Run shell commands', 'Read files'],
    createdAt: T - 90 * 86400e3, lastAt: T - 600e3, preview: 'Here is the plan, in order',
  },
  {
    id: 'b-coder', name: 'Coder', role: 'Builds and fixes', color: 'cyan', avatar: { shape: 'hex' },
    model: 'deepseek-official/deepseek-v4.1', sessionId: 's-coder',
    createdAt: T - 55 * 86400e3, lastAt: T - 5400e3,
    // Blocked on purpose: the second Bot covers the state the fixture must survive.
    blocked: { code: 'auth', provider: 'deepseek-official', status: 401 },
  },
]

const rooms = [
  {
    id: 'r-launch', name: 'Launch plan', members: ['b-chief', 'b-coder'], admin: 'b-chief',
    mode: 'admin', notice: 'Ship the release with green tests.', named: true,
    preview: 'Coder: Landing page draft is up', lastAt: T - 900e3, createdAt: T - 20 * 86400e3,
  },
]

const markdown = [
  '### Release plan',
  '',
  'Here is the plan I would take to production:',
  '',
  '- Pairing moved to the **Settings → Phone** card',
  '- The team list polls \u0060state\u0060 every three seconds',
  '- Writer runs on deepseek-official/deepseek-flash for drafts',
  '',
  '| Screen | Variant A | Variant B | Variant C |',
  '|---|---|---|---|',
  '| Team list | Tab | Drawer | Rail |',
  '| Chat | Bubble | Flat | Card |',
  '',
  '\u0060\u0060\u0060ts',
  "const page = await call('chat', { botId, steps: true })",
  '\u0060\u0060\u0060',
  '',
  'Worth a read: the [design notes](https://dsbot.app).',
].join('\n')

const chiefItems = [
  { kind: 'user', text: 'Ship the list first, then the drawer comparison.', time: T - 3400e3, seq: nextSeq(), turn: 3 },
  { kind: 'bot', text: markdown, time: T - 3300e3, seq: nextSeq(), turn: 3 },
  {
    kind: 'view', title: 'Coverage this week', time: T - 3000e3, seq: nextSeq(), turn: 4,
    view: { type: 'stack', children: [
      { type: 'metric', label: 'Cases passing', value: 186, caption: 'of 191 total' },
      { type: 'table', columns: ['Suite', 'Pass', 'Fail'], rows: [['Unit', 142, 2], ['Link', 20, 0], ['Mobile', 24, 3]] },
      { type: 'chart', kind: 'bar', categories: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        series: [{ name: 'Merged', values: [3, 5, 2, 7, 4] }, { name: 'Open', values: [6, 4, 5, 3, 2] }], unit: ' PRs' },
    ] },
  },
  {
    kind: 'user', text: 'Here is the screenshot from the phone', time: T - 2600e3, seq: nextSeq(), turn: 4,
    images: 1, imageRefs: [{ attachmentId: 'demo-img-1', mime: 'image/png', name: 'coverage.png' }],
  },
  {
    kind: 'answer', time: T - 2400e3, seq: nextSeq(), turn: 4,
    questions: [{ question: 'Which build should the phone use?' }],
    answers: [{ selected: ['The debug build'] }],
  },
  { kind: 'bot', text: 'Release notes are in. I am holding the tag until the screenshots land.', time: T - 1800e3, seq: nextSeq(), turn: 5 },
]

const roomItems = [
  { kind: 'event', role: 'request', name: 'Chief', time: T - 4000e3, seq: nextSeq() },
  { kind: 'bot', name: 'Coder', text: 'Landing page draft is up for review.\n\n- Hero copy\n- Pricing table\n- Footer links', time: T - 3800e3, seq: nextSeq(), turn: 2 },
  { kind: 'user', text: 'Tighten the pricing table, then I will look.', time: T - 3600e3, seq: nextSeq(), turn: 2 },
  {
    kind: 'view', title: 'Release readiness', time: T - 3400e3, seq: nextSeq(), turn: 3,
    view: { type: 'options', id: 'a-1', options: [{ label: 'Ship Friday' }, { label: 'Hold for Monday' }, { label: 'Cancel the tag' }] },
  },
  { kind: 'steps', turn: 3, ms: 12400, time: T - 3200e3, seq: nextSeq(), tools: [
    { name: 'read_file', label: 'Opening a file', ok: true },
    { name: 'run_command', label: 'Running shell commands', ok: true },
  ] },
  { kind: 'bot', name: 'Chief', text: 'Two things left before the tag: the migration approval and the screenshots.', time: T - 3000e3, seq: nextSeq(), turn: 3 },
]

const state = {
  revision: 1,
  bots,
  rooms,
  questions: {
    's-chief': {
      id: 'q-1',
      question: 'Which build should the phone use?',
      detail: 'I finished all three drafts.',
      options: [{ label: 'The debug build' }, { label: 'The release build' }],
    },
  },
  secretRequests: {},
  work: {
    bots: { 'b-chief': { tool: 'run_command', said: 'Running the test suite' } },
    rooms: {},
    approvals: [],
    waiting: {},
    turns: {},
  },
  activity: { 'b-chief': { tool: 'run_command', said: 'Running the test suite' } },
  browserHolds: {},
  btwCards: {},
  sideChats: {},
  connectors: [{ id: 'github', name: 'GitHub', state: 'ready', account: 'you' }],
  capabilityStatuses: {
    'b-chief': { 'Run shell commands': { state: 'ready' }, 'Read files': { state: 'ready' } },
  },
  capabilities: [
    { name: 'Run shell commands', description: 'Run terminal commands on the computer', kind: 'mcp', transport: 'stdio' },
    { name: 'Read files', description: 'Read files inside the working folder', kind: 'mcp', transport: 'stdio' },
  ],
  workspace: '/work',
  dataPath: '~/Library/Application Support/ds-bot',
  version: '0.1.2',
  models: [
    { ref: 'deepseek-official/deepseek-v4.1', name: 'DeepSeek v4.1' },
    { ref: 'deepseek-official/deepseek-flash', name: 'DeepSeek Flash' },
  ],
  defaultModel: 'deepseek-official/deepseek-v4.1',
  mainBotId: 'b-chief',
  mainBotIds: ['b-chief'],
  views: {},
  exchangeTurns: {},
  prefs: { theme: 'deepseek' },
}

const chats = {
  'b-chief': { sessionId: 's-chief', cursor: null, items: chiefItems },
  'b-coder': { sessionId: 's-coder', cursor: null, items: [] },
  'r-launch': { sessionId: 'r-launch', cursor: null, items: roomItems },
}

const capabilities = ['state', 'chat', 'room-chat', 'send', 'notices', 'questions', 'views', 'images', 'stop-chat']

function ok(value) { return { ok: true, value } }
function fail(code, message) { return { ok: false, error: { code, message } } }

const endpoints = {
  hello: () => ok({ api: 1, min: 1, boot: 'demo', seq: 0, capabilities }),
  notices: () => ok({ boot: 'demo', seq: 0, notices: [], reset: false }),
  state: () => ok(state),
  chat: (payload) => {
    const page = chats[String(payload?.botId ?? '')]
    return page ? ok({ sessionId: page.sessionId, items: page.items, cursor: page.cursor }) : fail('bot/not-found', 'Unknown Bot')
  },
  'room-chat': (payload) => {
    const page = chats[String(payload?.roomId ?? '')]
    return page
      ? ok({ roomId: payload.roomId, sessionId: page.sessionId, items: page.items, cursor: page.cursor, running: false, speaking: null })
      : fail('bot/not-found', 'Unknown room')
  },
  image: () => ok({ mime: 'image/png', data: image }),
  send: () => ok(true),
}

// ---------------------------------------------------------------- host

const keys = generateKeyPair()
const identity = { deviceId: deviceIdFor(keys.publicKey), ...keys }

let calls = 0
const link = new HostLink({
  url,
  identity,
  accessToken: randomToken(),
  name: 'CI Computer',
  // The fixture has nothing to protect, so any phone that finds it is welcome.
  admits: () => true,
  authorize: () => true,
  // The phone sends method "bot" with { endpoint, payload } inside it, exactly like
  // BotAPI.call does, so the endpoint lives one level down.
  handle: async (method, params) => {
    calls += 1
    const endpoint = method === 'bot' ? String(params?.endpoint ?? '') : method
    const payload = method === 'bot' ? (params?.payload ?? {}) : params
    const handler = endpoints[endpoint]
    const reply = handler ? handler(payload) : ok(null)
    console.log('screens host: ' + endpoint + ' -> ' + (reply.ok ? 'ok' : 'error ' + reply.error.code))
    return reply
  },
  onStatus: (status) => console.log('screens host: status ' + status),
  retryMs: [100, 500],
})

function pairingJson() {
  return JSON.stringify({
    activeId: identity.deviceId,
    computers: [{
      server: url,
      hostDeviceId: identity.deviceId,
      hostKey: identity.publicKey,
      code: '',
      name: 'CI Computer',
    }],
  })
}

function pairingPlist() {
  const data = Buffer.from(pairingJson(), 'utf8').toString('base64')
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '  <key>dsbot.pairing.offers</key>',
    '  <data>' + data + '</data>',
    '</dict>',
    '</plist>',
    '',
  ].join('\n')
}

async function writePairing() {
  await mkdir(outDir, { recursive: true })
  await writeFile(resolve(outDir, 'pairing.json'), pairingJson() + '\n', 'utf8')
  await writeFile(resolve(outDir, 'pairing.plist'), pairingPlist(), 'utf8')
  await writeFile(resolve(outDir, 'state.json'), JSON.stringify(state, null, 2) + '\n', 'utf8')
  console.log('screens host: pairing written to ' + resolve(outDir, 'pairing.plist'))
}

let stopping = false
async function stop(signal) {
  if (stopping) return
  stopping = true
  console.log('screens host: ' + signal + ', stopping after ' + calls + ' call(s)')
  try { await link.stop() } catch (error) { console.log('screens host: stop failed: ' + String(error)) }
  process.exit(0)
}
process.once('SIGTERM', () => { void stop('SIGTERM') })
process.once('SIGINT', () => { void stop('SIGINT') })

console.log('screens host: relay ' + url)
console.log('screens host: device ' + identity.deviceId)

link.start()
try {
  await link.waitOnline(onlineTimeoutMs)
} catch (error) {
  console.log('screens host: the relay never answered: ' + String(error))
  process.exit(1)
}
await writePairing()
console.log('screens host: online, waiting for the app')

await new Promise(() => {})
