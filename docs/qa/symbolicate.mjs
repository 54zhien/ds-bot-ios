#!/usr/bin/env node
// Symbolicate an iOS crash report (.ips or .crash) against a directory of dSYMs.
//
// Why this exists: TestFlight and Xcode hand out reports whose frames are bare
// addresses, and only the dSYM built with that exact binary turns them back into
// function names and source lines. A release keeps PRODUCT_NAME.app.dSYM next to
// its .xcarchive plus one dSYM per framework, so this script takes that directory
// and finds each image by UUID first, by image name second.
//
// atos ships with the Xcode command line tools, so this script runs on macOS only.
// It has never run against a device build of this app: docs/qa/symbolicate.md
// marks it 未验证. On Windows the parsers still work and --dry-run prints the plan.
//
// usage: node symbolicate.mjs CRASH --dsym DIR [--arch arm64] [--all] [--dry-run] [--json]

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { basename, join } from 'node:path'

const USAGE = [
  'usage: node symbolicate.mjs CRASH --dsym DIR [--arch ARCH] [--all] [--dry-run] [--json]',
  '',
  '  CRASH       .ips (iOS 15 and later) or a legacy .crash text report',
  '  --dsym DIR  directory holding DSBot.app.dSYM and each *.framework.dSYM',
  '  --arch A    arm64 (default) or arm64e, the slice that crashed',
  '  --all       every thread, not only the crashed one',
  '  --dry-run   parse and print the atos commands, run none of them',
  '  --json      print the parsed and resolved frames as JSON',
].join('\n')

// A frame in a legacy report carries both the absolute address and the load
// address of its image, which is exactly what atos -l wants.
const FRAME = /^\s*(\d+)\s+(\S+)\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+|0)\s+\+\s+(\d+)\s*$/
// Binary Images: a start and end address, then "+Name arch <UUID> path".
const IMAGE = /^(0x[0-9a-fA-F]+)\s+-\s+(0x[0-9a-fA-F]+)\s+\+?(\S+)\s+(\S+)\s+<([0-9A-Fa-f-]+)>\s+(.+)$/
const THREAD_HEAD = /^Thread (\d+)( Crashed)?:?\s*$/
const THREAD_NAME = /^Thread (\d+) name:\s*(.+)$/
const HEADER = /^(Incident Identifier|Process|Version|OS Version|Hardware Model|Exception Type|Triggered by Thread|Bug Type):\s*(.+)$/

function tryJson(text) {
  try { return JSON.parse(text) } catch { return undefined }
}

function toInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value)
  if (typeof value === 'string') {
    const text = value.trim()
    if (text === '') return 0
    return /^0x/i.test(text) ? parseInt(text.slice(2), 16) : parseInt(text, 10)
  }
  return 0
}

function hex(value) {
  return '0x' + toInt(value).toString(16)
}

function parseArgs(argv) {
  const opts = { arch: 'arm64', all: false, dry: false, json: false, help: false }
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    const next = () => { index += 1; return argv[index] }
    if (arg === '--help' || arg === '-h') opts.help = true
    else if (arg === '--dsym') opts.dsym = next()
    else if (arg === '--arch') opts.arch = next()
    else if (arg === '--all') opts.all = true
    else if (arg === '--dry-run') opts.dry = true
    else if (arg === '--json') opts.json = true
    else if (arg.startsWith('--dsym=')) opts.dsym = arg.slice(7)
    else if (arg.startsWith('--arch=')) opts.arch = arg.slice(7)
    else if (arg.startsWith('-')) throw new Error('unknown option ' + arg)
    else if (opts.crash === undefined) opts.crash = arg
    else throw new Error('unexpected argument ' + arg)
  }
  if (opts.dsym !== undefined && opts.dsym.trim() === '') throw new Error('--dsym needs a directory')
  return opts
}

// iOS 15 and later write JSON: one header object, a newline, then the report. The
// older tools wrote a second line that is the whole report, so both are tried.
function parseIps(text) {
  const clean = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text
  let header = {}
  let body = tryJson(clean)
  if (body === undefined) {
    const cut = clean.indexOf('\n')
    if (cut < 0) throw new Error('not a JSON crash report')
    header = tryJson(clean.slice(0, cut)) ?? {}
    body = tryJson(clean.slice(cut + 1))
    if (body === undefined) throw new Error('the body of the .ips is not JSON')
  }
  const images = (body.usedImages ?? []).map((image, index) => ({
    index,
    base: toInt(image.base),
    uuid: String(image.uuid ?? '').toLowerCase(),
    name: String(image.name ?? basename(String(image.path ?? ''))),
    path: String(image.path ?? ''),
    arch: String(image.arch ?? ''),
  }))
  const threads = (body.threads ?? []).map(thread => ({
    id: toInt(thread.id),
    crashed: thread.triggered === true,
    name: String(thread.name ?? thread.queue ?? ''),
    frames: (thread.frames ?? []).map((frame, order) => {
      const index = toInt(frame.imageIndex)
      const image = images[index]
      const offset = toInt(frame.imageOffset)
      return {
        order,
        imageIndex: index,
        base: image === undefined ? 0 : image.base,
        offset,
        address: (image === undefined ? 0 : image.base) + offset,
        symbol: String(frame.symbol ?? ''),
        file: String(frame.sourceFile ?? ''),
        line: toInt(frame.sourceLine),
      }
    }),
  }))
  return {
    kind: 'ips',
    bug: String(body.bug_type ?? header.bug_type ?? ''),
    incident: String(body.incident ?? header.incident_id ?? ''),
    process: {
      name: String(body.procName ?? header.app_name ?? ''),
      version: String(header.app_version ?? ''),
      build: String(header.build_version ?? ''),
      os: String(header.os_version ?? ''),
      model: String(header.modelCode ?? body.modelCode ?? ''),
    },
    images,
    threads,
  }
}

// The legacy text report: headers, one block per thread, then Binary Images at the
// bottom. Frames come before the image table, so they are matched afterwards.
function parseCrash(text) {
  const lines = text.split(/\r?\n/)
  const head = {}
  const images = []
  const threads = []
  const raw = []
  let current = null
  let inImages = false
  for (const line of lines) {
    if (line.startsWith('Binary Images:')) {
      inImages = true
      current = null
      continue
    }
    if (inImages) {
      const image = IMAGE.exec(line)
      if (image !== null) {
        images.push({
          index: images.length,
          base: parseInt(image[1], 16),
          end: parseInt(image[2], 16),
          uuid: image[5].toLowerCase(),
          name: image[3],
          path: image[6].trim(),
          arch: image[4],
        })
      }
      continue
    }
    const header = HEADER.exec(line)
    if (header !== null) head[header[1]] = header[2].trim()
    const named = THREAD_NAME.exec(line)
    if (named !== null) {
      const id = parseInt(named[1], 10)
      let thread = threads.find(entry => entry.id === id)
      if (thread === undefined) {
        thread = { id, crashed: false, name: '', frames: [] }
        threads.push(thread)
      }
      thread.name = named[2].trim()
      continue
    }
    const threadHead = THREAD_HEAD.exec(line)
    if (threadHead !== null) {
      const id = parseInt(threadHead[1], 10)
      // "Thread 0 name:" comes first in some reports and "Thread 0 Crashed:" after
      // it, so the two lines describe one thread; only a block with frames is new.
      const known = threads.find(entry => entry.id === id && entry.frames.length === 0)
      current = known ?? { id, crashed: false, name: '', frames: [] }
      current.crashed = threadHead[2] !== undefined
      if (known === undefined) threads.push(current)
      continue
    }
    if (current !== null) {
      const frame = FRAME.exec(line)
      if (frame !== null) {
        const address = parseInt(frame[3], 16)
        const base = frame[4] === '0' ? 0 : parseInt(frame[4], 16)
        const entry = { order: current.frames.length, imageIndex: -1, base, offset: 0, address, symbol: '', file: '', line: 0 }
        entry.offset = base === 0 ? 0 : address - base
        current.frames.push(entry)
        raw.push(entry)
        continue
      }
      if (line.trim() !== '') current = null
    }
  }
  for (const frame of raw) {
    const image = images.find(entry => entry.base === frame.base)
    if (image !== undefined) frame.imageIndex = image.index
  }
  const process = String(head.Process ?? '')
  const match = /^(\S+)\s+\[(\d+)\]$/.exec(process)
  return {
    kind: 'crash',
    bug: String(head['Bug Type'] ?? ''),
    incident: String(head['Incident Identifier'] ?? ''),
    process: {
      name: match === null ? process : match[1],
      version: String(head.Version ?? ''),
      build: '',
      os: String(head['OS Version'] ?? ''),
      model: String(head['Hardware Model'] ?? ''),
    },
    images,
    threads,
  }
}

function parseReport(text) {
  const trimmed = text.replace(/^\uFEFF/, '').trimStart()
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return parseIps(text)
  if (text.includes('Binary Images:')) return parseCrash(text)
  throw new Error('neither a JSON .ips nor a text .crash report')
}

// Every dSYM in the directory, one entry per DWARF binary inside it. A dSYM holds
// the same name as the image it belongs to: DSBot.app.dSYM, DeepView.framework.dSYM.
function scanDsyms(root) {
  const found = []
  const walk = (dir, depth) => {
    if (depth > 6) return
    let entries
    try { entries = readdirSync(dir, { withFileTypes: true }) } catch { return }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue
      const full = join(dir, entry.name)
      if (entry.name.endsWith('.dSYM')) {
        const dwarf = join(full, 'Contents', 'Resources', 'DWARF')
        if (!existsSync(dwarf)) continue
        for (const file of readdirSync(dwarf)) {
          found.push({ binary: join(dwarf, file), image: file, dsym: full })
        }
        continue
      }
      walk(full, depth + 1)
    }
  }
  walk(root, 0)
  return found
}

// UUIDs come from dwarfdump, which lives with atos on macOS. Without it the match
// falls back to the image name, which is enough while only one build is around.
const uuids = new Map()
function uuidOf(binary) {
  if (uuids.has(binary)) return uuids.get(binary)
  let list = []
  try {
    const out = execFileSync('dwarfdump', ['--uuid', binary], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
    list = [...out.matchAll(/UUID:\s*([0-9A-Fa-f-]{36})\s*\(([^)]+)\)/g)].map(match => ({ uuid: match[1].toLowerCase(), arch: match[2] }))
  } catch { list = [] }
  uuids.set(binary, list)
  return list
}

function pickBinary(entries, image, arch) {
  const wanted = image.uuid
  if (wanted !== '') {
    for (const entry of entries) {
      if (uuidOf(entry.binary).some(one => one.uuid === wanted && (one.arch === arch || arch === ''))) return entry
    }
  }
  const named = entries.filter(entry => entry.image.toLowerCase() === image.name.toLowerCase())
  if (named.length === 0) return undefined
  const exact = named.find(entry => uuidOf(entry.binary).some(one => one.arch === arch))
  return exact ?? named[0]
}

function atosArgs(binary, base, addresses, arch) {
  return ['-arch', arch, '-o', binary, '-l', hex(base), ...addresses.map(hex)]
}

function runAtos(binary, base, addresses, arch) {
  const out = execFileSync('atos', atosArgs(binary, base, addresses, arch), {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 32 * 1024 * 1024,
  })
  return out.split(/\r?\n/).filter(line => line.trim() !== '')
}

function main() {
  let opts
  try { opts = parseArgs(process.argv.slice(2)) } catch (error) {
    console.error(String(error.message))
    console.error(USAGE)
    return 2
  }
  if (opts.help || opts.crash === undefined) {
    console.log(USAGE)
    return opts.help ? 0 : 2
  }
  if (!existsSync(opts.crash)) {
    console.error('no such crash report: ' + opts.crash)
    return 3
  }
  let report
  try { report = parseReport(readFileSync(opts.crash, 'utf8')) } catch (error) {
    console.error('cannot read ' + opts.crash + ': ' + String(error.message))
    return 3
  }

  const entries = opts.dsym === undefined ? [] : scanDsyms(opts.dsym)
  if (opts.dsym !== undefined && entries.length === 0) console.error('note: no dSYM under ' + opts.dsym)
  if (opts.dsym === undefined) console.error('note: no --dsym given, frames stay raw')

  const binaries = new Map()
  for (const image of report.images) {
    const entry = pickBinary(entries, image, opts.arch)
    if (entry !== undefined) binaries.set(image.index, entry)
  }

  const warnings = []
  for (const image of report.images) {
    const frames = report.threads.some(thread => thread.frames.some(frame => frame.imageIndex === image.index))
    if (!frames) continue
    if (!binaries.has(image.index) && entries.length > 0) {
      warnings.push('no dSYM for ' + (image.name || image.path) + ' (' + (image.uuid || 'no uuid') + ')')
    }
  }

  // One atos call per image and thread keeps the process count low; addresses are
  // chunked so a long stack never grows the argument list past the OS limit.
  const plan = []
  for (const thread of report.threads) {
    if (!opts.all && !thread.crashed) continue
    const byImage = new Map()
    for (const frame of thread.frames) {
      const entry = binaries.get(frame.imageIndex)
      if (entry === undefined) continue
      const list = byImage.get(frame.imageIndex) ?? []
      list.push(frame)
      byImage.set(frame.imageIndex, list)
    }
    for (const [index, frames] of byImage) {
      const entry = binaries.get(index)
      const image = report.images[index]
      for (let at = 0; at < frames.length; at += 200) {
        plan.push({ thread, entry, image, frames: frames.slice(at, at + 200) })
      }
    }
  }

  const commands = plan.map(job => ['atos', ...atosArgs(job.entry.binary, job.image.base, job.frames.map(frame => frame.address), opts.arch)])
  let atosMissing = false
  if (!opts.dry && plan.length > 0) {
    for (const job of plan) {
      try {
        const lines = runAtos(job.entry.binary, job.image.base, job.frames.map(frame => frame.address), opts.arch)
        job.frames.forEach((frame, at) => { frame.resolved = lines[at] ?? '' })
      } catch (error) {
        if (error.code === 'ENOENT') { atosMissing = true; break }
        warnings.push('atos failed for ' + job.entry.image + ': ' + String(error.message).split('\n')[0])
      }
    }
  }
  if (atosMissing) warnings.push('atos is not on this machine: frames stay raw (Windows cannot run atos; use macOS)')

  if (opts.json) {
    console.log(JSON.stringify({ report: { bug: report.bug, incident: report.incident, process: report.process }, warnings, commands }, null, 2))
    return 0
  }

  const out = []
  const info = report.process
  const stamp = [info.version !== '' ? info.version + (info.build !== '' ? ' (' + info.build + ')' : '') : '', info.os, opts.arch].filter(part => part !== '')
  out.push('crash     ' + opts.crash + (report.kind === 'ips' ? '  [.ips]' : '  [.crash]'))
  out.push('process   ' + (info.name || 'unknown') + (stamp.length > 0 ? '  ' + stamp.join(' · ') : ''))
  if (report.incident !== '') out.push('incident  ' + report.incident)
  out.push('dSYM      ' + (opts.dsym === undefined ? '(none)' : entries.length + ' binaries under ' + opts.dsym))
  out.push('')

  const fmt = (text, width) => (text.length >= width ? text : text + ' '.repeat(width - text.length))
  const nameWidth = Math.min(24, Math.max(12, ...report.images.map(image => image.name.length)))
  for (const thread of report.threads) {
    if (!opts.all && !thread.crashed) continue
    out.push('Thread ' + thread.id + (thread.crashed ? ' (crashed)' : '') + (thread.name !== '' ? '  ' + thread.name : ''))
    for (const frame of thread.frames) {
      const image = report.images[frame.imageIndex]
      const name = image === undefined ? '?' : image.name
      const body = frame.resolved !== undefined && frame.resolved !== ''
        ? frame.resolved
        : (frame.symbol !== '' ? frame.symbol + (frame.file !== '' ? '  (' + frame.file + ':' + frame.line + ')' : '') : '(no symbol)')
      out.push('  #' + String(frame.order).padStart(3, ' ') + '  ' + hex(frame.address) + '  ' + fmt(name, nameWidth) + '  ' + body)
    }
    out.push('')
  }

  if (opts.dry || atosMissing) {
    out.push('atos commands (not run: ' + (opts.dry ? '--dry-run' : 'atos missing') + ')')
    if (commands.length === 0) out.push('  (no frame matched a dSYM)')
    for (const command of commands) out.push('  ' + command.map(part => (/[\s]/.test(part) ? JSON.stringify(part) : part)).join(' '))
    out.push('')
  }
  if (warnings.length > 0) {
    out.push('warnings')
    for (const warning of warnings) out.push('  - ' + warning)
  }
  console.log(out.join('\n').replace(/\s+$/, ''))
  return 0
}

process.exitCode = main()
