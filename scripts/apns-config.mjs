#!/usr/bin/env node
// The APNs credentials step of docs/host-push.md §0, for the window between now and the
// desktop settings panel that calls `phone-push-set`. It writes the same `push.config`
// shape that endpoint writes, after the same checks.
//
// The host reads phone.json once at startup and saves its own copy over it, so a write
// while DS Bot runs would be lost on the next save: this refuses to touch the file then.
//
//   node scripts/apns-config.mjs --key [P8_PATH] --key-id [APNS_KEY_ID] --team-id [TEAM_ID]
//                                [--topic [APNS_TOPIC]] [--sound default|none] [--dry-run]
//   node scripts/apns-config.mjs --check
//   node scripts/apns-config.mjs --clear
//
// `--phone` points the script at another file, for tests.
import { createPrivateKey } from 'node:crypto'
import { copyFileSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { createConnection } from 'node:net'
import { homedir } from 'node:os'
import { join, resolve } from 'node:path'

const has = flag => process.argv.includes(flag)
const option = (name) => {
  const at = process.argv.indexOf(name)
  if (at < 0) return undefined
  const value = process.argv[at + 1]
  if (value === undefined || value.startsWith('--')) stop(`${name} needs a value`)
  return value
}
function stop(message) {
  console.error(`apns-config: ${message}`)
  process.exit(1)
}

const dshHome = process.env.DSH_HOME?.trim() || join(homedir(), '.dsh')
const phonePath = resolve(option('--phone') ?? join(dshHome, 'bot', 'phone.json'))
const portFile = join(process.env.APPDATA?.trim() || join(homedir(), 'AppData', 'Roaming'), 'DS Bot', 'host-port.json')

// The host holds the file in memory and saves over it; an edit now would vanish.
async function hostRunning() {
  let port
  try { port = JSON.parse(readFileSync(portFile, 'utf8')).port } catch { return false }
  if (!Number.isInteger(port)) return false
  return await new Promise((done) => {
    const socket = createConnection({ host: '127.0.0.1', port })
    const settle = (open) => { socket.destroy(); done(open) }
    socket.setTimeout(800, () => settle(false))
    socket.once('connect', () => settle(true))
    socket.once('error', () => settle(false))
  })
}

function readPhone() {
  let text
  try { text = readFileSync(phonePath, 'utf8') } catch (error) {
    if (error.code === 'ENOENT') stop(`no phone.json at ${phonePath}: start DS Bot once, quit it, and run this again`)
    throw error
  }
  try { return kept(JSON.parse(text)) } catch (error) {
    stop(`${phonePath} is not JSON (${error.message}); fix or restore it first`)
  }
}

// Same normalization `phone.js` applies on read, so a file written here needs no repair.
function kept(data) {
  if (typeof data.push !== 'object' || data.push === null || Array.isArray(data.push)) data.push = {}
  if (typeof data.push.tokens !== 'object' || data.push.tokens === null || Array.isArray(data.push.tokens)) data.push.tokens = {}
  return data
}

function writePhone(data) {
  if (has('--dry-run')) {
    console.log(`dry run: would write ${phonePath}`)
    return undefined
  }
  // Local time, because the user reads the backup name, not a log viewer.
  const now = new Date()
  const pad = value => String(value).padStart(2, '0')
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
  const backup = `${phonePath}.bak-${stamp}`
  copyFileSync(phonePath, backup)
  const temp = `${phonePath}.${process.pid}.tmp`
  writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 })
  renameSync(temp, phonePath)
  return backup
}

const status = record => (record.unregisteredAt === undefined ? 'live' : 'retired')
function keyState(config) {
  if (typeof config.keyPath !== 'string') return 'not named'
  try { createPrivateKey(readFileSync(config.keyPath)); return 'readable' } catch { return 'unreadable now' }
}

function showConfig(data) {
  const list = Object.entries(data.push.tokens)
  const config = data.push.config
  console.log(`phone.json   ${phonePath}`)
  if (config === undefined) {
    console.log('push         not configured: the host logs one "push skipped: no key configured"')
  } else {
    console.log('push         configured')
    console.log(`key path     ${config.keyPath}  (${keyState(config)})`)
    console.log(`key id       ${config.keyId}`)
    console.log(`team id      ${config.teamId}`)
    console.log(`topic        ${config.topic ?? '(each phone names its own bundle id)'}`)
    console.log(`sound        ${config.sound ?? 'default'}`)
  }
  console.log(`tokens       ${list.length === 0 ? 'none: turn push on in the phone app' : list.map(([, record]) => status(record)).join(', ')}`)
  for (const [deviceId, record] of list) {
    console.log(`             ${deviceId}  ${record.env}  ${record.bundleId}  ${status(record)}`)
  }
}

if (has('--check')) {
  showConfig(readPhone())
  console.log(`DS Bot       ${await hostRunning() ? 'running' : 'not running'}`)
  process.exit(0)
}

if (has('--clear')) {
  if (await hostRunning()) stop('DS Bot is running: quit it first (tray icon, Quit), run this again, then start DS Bot')
  const data = readPhone()
  if (data.push.config === undefined) {
    console.log(`nothing to clear: ${phonePath} has no push config`)
    process.exit(0)
  }
  delete data.push.config
  const backup = writePhone(data)
  console.log(`cleared push config in ${phonePath}`)
  if (backup !== undefined) console.log(`backup     ${backup}`)
  process.exit(0)
}

const keyArg = option('--key')
if (keyArg === undefined) stop('--key [P8_PATH] is required (the AuthKey_XXXXXXXXXX.p8 Apple gave you)')
const keyId = String(option('--key-id') ?? '').trim().toUpperCase()
const teamId = String(option('--team-id') ?? '').trim().toUpperCase()
const topic = option('--topic')?.trim()
const sound = option('--sound') ?? 'default'
if (!/^[A-Za-z0-9]{10}$/u.test(keyId)) stop('--key-id must be the 10 characters from the developer portal')
if (!/^[A-Za-z0-9]{10}$/u.test(teamId)) stop('--team-id must be the 10 characters from the developer portal')
if (topic !== undefined && (topic === '' || topic.length > 256)) stop('--topic must be a bundle id')
if (sound !== 'default' && sound !== 'none') stop('--sound must be default or none')

const keyPath = resolve(keyArg)
// The same check `phone-push-set` makes: an unreadable p8 is refused here, not at the
// first push, where it would surface as InvalidProviderToken and look like a wrong key id.
try { createPrivateKey(readFileSync(keyPath)) } catch {
  stop(`${keyPath} cannot be read as an EC private key (is it the .p8 Apple gave you?)`)
}

if (await hostRunning()) stop('DS Bot is running: quit it first (tray icon, Quit), run this again, then start DS Bot')

const data = readPhone()
data.push.config = {
  keyPath,
  keyId,
  teamId,
  ...(topic !== undefined ? { topic } : {}),
  sound: sound === 'none' ? 'none' : 'default',
}
const backup = writePhone(data)
console.log(`configured push in ${phonePath}`)
console.log(`  key path   ${keyPath}`)
console.log(`  key id     ${keyId}`)
console.log(`  team id    ${teamId}`)
console.log(`  topic      ${topic ?? '(each phone names its own bundle id)'}`)
console.log(`  sound      ${data.push.config.sound}`)
if (backup !== undefined) console.log(`backup     ${backup}`)
console.log('next       start DS Bot, then turn push on in the phone app')
