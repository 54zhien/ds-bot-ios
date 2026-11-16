// Regenerates every vector file in this directory from the real link/ implementation.
// Run: node docs/link-test-vectors/generate.mjs   (Node 24, no build step)
//
// Everything below is produced by calling the shipped code, never by hand. The only
// injected input is randomness: the handshake vector pins the RNG so the bytes are
// reproducible. The app itself uses crypto randomness (src/noise.ts:44).
import { createHash } from 'node:crypto'
import { writeFileSync } from 'node:fs'

const link = path => new URL('../../link/' + path, import.meta.url).href
const L = await import(link('src/index.ts'))
const Relay = await import(link('server/server.ts'))

const PROTOCOL = L.PROTOCOL_VERSION
const CONNECTION_ID = 'conn-vector-1'
const TS = 1893456000000 // 2030-01-01T00:00:00Z, so no generated file depends on the clock

// ---------------------------------------------------------------- fixed inputs
const phoneKeys = L.generateKeyPair(Uint8Array.from({ length: 32 }, (_, i) => i + 1))
const hostKeys = L.generateKeyPair(Uint8Array.from({ length: 32 }, (_, i) => 0xa0 + i))
const phoneDevice = L.deviceIdFor(phoneKeys.publicKey)
const hostDevice = L.deviceIdFor(hostKeys.publicKey)
const accessToken = L.toBase64Url(Uint8Array.from({ length: 32 }, (_, i) => 0x42 + (i % 7)))

/** A pinned random source: call n returns sha256(tag || n) truncated, so every run matches. */
function pinnedRandom(tag) {
  let n = 0
  return (length) => {
    const counter = Buffer.from([n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff])
    n += 1
    return new Uint8Array(createHash('sha256').update(Buffer.concat([Buffer.from(tag), counter])).digest().subarray(0, length))
  }
}

const hex = bytes => Buffer.from(bytes).toString('hex')
const sha256hex = bytes => createHash('sha256').update(Buffer.from(bytes)).digest('hex')
const b64 = bytes => L.toBase64Url(bytes)
const text = value => new TextEncoder().encode(value)
const decodeText = bytes => new TextDecoder().decode(bytes)

// ------------------------------------------------------------------- handshake
const prologue = L.createNoisePrologue(CONNECTION_ID, hostDevice, phoneDevice)
const phoneHello = { name: 'Phone (vector)' }
const hostHello = { name: 'Desk (vector)' }

const phone = new L.NoiseIkSession({
  role: 'initiator', localPrivateKey: phoneKeys.privateKey, localPublicKey: phoneKeys.publicKey,
  remotePublicKey: hostKeys.publicKey, prologue, random: pinnedRandom('phone'),
})
const host = new L.NoiseIkSession({
  role: 'responder', localPrivateKey: hostKeys.privateKey, localPublicKey: hostKeys.publicKey,
  remotePublicKey: phoneKeys.publicKey, prologue, random: pinnedRandom('host'),
})

const message1 = phone.writeHandshake(L.encodeHandshakeHello(phoneHello))
const helloSeenByHost = L.decodeHandshakeHello(host.readHandshake(message1))
const message2 = host.writeHandshake(L.encodeHandshakeHello(hostHello))
const helloSeenByPhone = L.decodeHandshakeHello(phone.readHandshake(message2))

const transport = phone.transport
const handshakeHash = transport.getHandshakeHash()
const proofPlaintext = 'DSBOT-PROOF'
const proofNonce = transport.sendingNonce()
const proofCiphertext = phone.encrypt(text(proofPlaintext))
const keys = transport.takeCiphers()
const initiatorToResponder = keys.initiatorToResponder.getKey()
const responderToInitiator = keys.responderToInitiator.getKey()

writeFileSync(new URL('./keys.json', import.meta.url), JSON.stringify({
  $comment: 'Noise IK (Noise_IK_25519_ChaChaPoly_SHA256) — handshake bytes, session keys and the first transport message.',
  source: {
    suite: L.NOISE_IK_PROTOCOL,
    prologue: 'src/noise.ts:127-134',
    handshake: 'src/noise.ts:53-68',
    transport: 'src/noise.ts:70-76',
  },
  pinnedRandom:
    'random(tag, n) = sha256(tag || uint24le(n))[0..len); tag is "phone" for the initiator, "host" for the responder. '
    + 'The first call per side yields its ephemeral private key; later calls are unused by IK, but the rule stays the same.',
  deviceIds: { phone: phoneDevice, host: hostDevice },
  keys: {
    phone: { privateKey: phoneKeys.privateKey, publicKey: phoneKeys.publicKey },
    host: { privateKey: hostKeys.privateKey, publicKey: hostKeys.publicKey },
  },
  connection: { connectionId: CONNECTION_ID, hostDeviceId: hostDevice, clientDeviceId: phoneDevice },
  prologue: { utf8: decodeText(prologue), hex: hex(prologue), bytes: prologue.byteLength },
  handshake: {
    message1: { from: 'initiator', payload: phoneHello, bytes: message1.byteLength, hex: hex(message1), base64url: b64(message1) },
    message1Decrypted: helloSeenByHost,
    message2: { from: 'responder', payload: hostHello, bytes: message2.byteLength, hex: hex(message2), base64url: b64(message2) },
    message2Decrypted: helloSeenByPhone,
    handshakeHash: { hex: hex(handshakeHash), bytes: handshakeHash.byteLength },
  },
  session: {
    initiatorToResponder: { hex: hex(initiatorToResponder), base64url: b64(initiatorToResponder) },
    responderToInitiator: { hex: hex(responderToInitiator), base64url: b64(responderToInitiator) },
    note: 'initiatorToResponder encrypts what the phone sends; responderToInitiator what the computer sends. '
      + 'A Swift session that reproduces message1/message2 must also reproduce these two keys.',
  },
  transportProof: {
    order: 0,
    nonce: String(proofNonce),
    plaintextUtf8: proofPlaintext,
    ciphertextHex: hex(proofCiphertext),
    ciphertextBytes: proofCiphertext.byteLength,
    note: 'First transport message of this session; the nonce advances to 1 afterwards. 12-byte tag appended, no AD.',
  },
}, null, 2) + '\n')

// ---------------------------------------------------------------------- frames
function frame(type, payload, id) {
  const created = L.createControlFrame(type, payload, id)
  created.timestamp = TS
  return created
}

const helloFrame = frame('hello', {
  role: 'client',
  deviceId: phoneDevice,
  identityKey: phoneKeys.publicKey,
  accessToken,
  protocols: [PROTOCOL],
  capabilities: ['transport.relay'],
}, 'vec-hello-1')

const relayCiphertext = Uint8Array.from({ length: 24 }, (_, i) => (i * 7 + 3) & 0xff)
const relayFrame = frame('relay', {
  connectionId: CONNECTION_ID,
  targetDeviceId: hostDevice,
  counter: 7,
  ciphertext: b64(relayCiphertext),
}, 'vec-relay-1')

const errorFrame = frame('error', {
  code: 'HOST_OFFLINE',
  message: 'The computer is offline.',
  retryable: true,
}, 'vec-error-1')

const encoded = [helloFrame, relayFrame, errorFrame].map(f => L.encodeControlFrame(f))

writeFileSync(new URL('./frames.json', import.meta.url), JSON.stringify({
  $comment: 'Control frames: the object, the exact encoded string, and the size each one must fit.',
  source: { encode: 'src/frames.ts:164-177', envelope: 'src/frames.ts:192-207', limits: 'src/frames.ts:308-314' },
  limits: {
    maxControlFrameBytes: L.MAX_CONTROL_FRAME_BYTES,
    maxRelayFrameBytes: L.MAX_RELAY_FRAME_BYTES,
    note: 'relay frames are held to maxRelayFrameBytes, every other type to maxControlFrameBytes; '
      + 'the Server announces both in hello.ack and a peer may only lower them (src/frames.ts:308-314).',
  },
  timestamp: TS,
  frames: [
    {
      name: 'hello',
      payload: helloFrame.payload,
      decoded: helloFrame,
      encoded: encoded[0],
      encodedBytes: Buffer.byteLength(encoded[0]),
    },
    {
      name: 'relay',
      payload: { ...relayFrame.payload, ciphertextSourceHex: hex(relayCiphertext) },
      decoded: relayFrame,
      encoded: encoded[1],
      encodedBytes: Buffer.byteLength(encoded[1]),
    },
    {
      name: 'error',
      payload: errorFrame.payload,
      decoded: errorFrame,
      encoded: encoded[2],
      encodedBytes: Buffer.byteLength(encoded[2]),
    },
  ],
  accepted: {
    accessToken,
    phoneDeviceId: phoneDevice,
    hostDeviceId: hostDevice,
    note: 'The Server derives the device id from identityKey and rejects a mismatch (server/gateway.ts:218-226).',
  },
}, null, 2) + '\n')

// ------------------------------------------------------------------ fragments
const MESSAGE_PATTERN = 'byte(i) = (i * 37 + 11) & 0xff'

function pattern(length) {
  return Uint8Array.from({ length }, (_, i) => (i * 37 + 11) & 0xff)
}

// A fresh session with the same transcript, so its transport starts at nonce 0.
function freshSession() {
  const phone2 = new L.NoiseIkSession({
    role: 'initiator', localPrivateKey: phoneKeys.privateKey, localPublicKey: phoneKeys.publicKey,
    remotePublicKey: hostKeys.publicKey, prologue, random: pinnedRandom('phone'),
  })
  const host2 = new L.NoiseIkSession({
    role: 'responder', localPrivateKey: hostKeys.privateKey, localPublicKey: hostKeys.publicKey,
    remotePublicKey: phoneKeys.publicKey, prologue, random: pinnedRandom('host'),
  })
  host2.readHandshake(phone2.writeHandshake(L.encodeHandshakeHello(phoneHello)))
  phone2.readHandshake(host2.writeHandshake(L.encodeHandshakeHello(hostHello)))
  return phone2
}

function encodeMessage(session, plaintext, startCounter) {
  const codec = new L.SecureMessageCodec()
  let counter = startCounter
  const out = []
  for (const fragment of codec.encode(plaintext)) {
    const nonce = session.transport.sendingNonce()
    const ciphertext = session.encrypt(fragment)
    const wire = frame('relay', {
      connectionId: CONNECTION_ID,
      targetDeviceId: hostDevice,
      counter,
      ciphertext: b64(ciphertext),
    }, 'vec-frag-' + counter)
    const wireJson = L.encodeControlFrame(wire)
    out.push({
      index: out.length,
      plaintextBytes: fragment.byteLength,
      plaintextIsFragment: fragment.byteLength !== plaintext.byteLength,
      ciphertextHex: hex(ciphertext),
      ciphertextBytes: ciphertext.byteLength,
      transportNonce: String(nonce),
      counter,
      wireFrameJson: wireJson,
      wireBytes: Buffer.byteLength(wireJson),
    })
    counter += 1
  }
  return out
}

const session = freshSession()
const small = pattern(4096)
const smallFrames = encodeMessage(session, small, 0)
const large = pattern(100 * 1024)
const largeFrames = encodeMessage(session, large, smallFrames.length)

function fragmentHeaders(plaintext, frames) {
  const codec = new L.SecureMessageCodec()
  const fragments = codec.encode(plaintext)
  return fragments.map((fragment, index) => ({
    index,
    bytes: fragment.byteLength,
    hexHead: hex(fragment.subarray(0, 17)),
    magic: 'DSBF',
    version: fragment[4],
    messageId: new DataView(fragment.buffer, fragment.byteOffset, fragment.byteLength).getUint32(5),
    fragmentIndex: new DataView(fragment.buffer, fragment.byteOffset, fragment.byteLength).getUint16(9),
    fragmentTotal: new DataView(fragment.buffer, fragment.byteOffset, fragment.byteLength).getUint16(11),
    totalBytes: new DataView(fragment.buffer, fragment.byteOffset, fragment.byteLength).getUint32(13),
  }))
}

writeFileSync(new URL('./fragments.json', import.meta.url), JSON.stringify({
  $comment: 'Chunking of one small and one large message, each fragment encrypted on the session from keys.json (fresh copy, nonces start at 0).',
  source: {
    codec: 'src/frames.ts:220-298',
    chunkBytes: L.SECURE_FRAGMENT_CHUNK_BYTES,
    maxMessageBytes: L.MAX_SECURE_MESSAGE_BYTES,
    session: 'fresh copy of the keys.json transcript; transport nonce starts at 0',
  },
  plaintextPattern: MESSAGE_PATTERN,
  small: {
    bytes: small.byteLength,
    sha256: sha256hex(small),
    fragments: fragmentHeaders(small, smallFrames),
    frames: smallFrames,
    note: '4096 bytes is below the 48 KiB chunk, so there is no DSBF header: the plaintext is the frame. '
      + 'A 4 KiB message therefore cannot show fragmentation — that is why the 100 KiB case exists.',
  },
  large: {
    bytes: large.byteLength,
    sha256: sha256hex(large),
    fragments: fragmentHeaders(large, largeFrames),
    frames: largeFrames,
    note: '102400 bytes splits into 49152 + 49152 + 4096, three frames, in order. The last one is short.',
  },
}, null, 2) + '\n')

// ------------------------------------------------------------------ rejections
class Peer {
  constructor() { this.queue = []; this.waiters = [] }
  static async open(url) {
    const peer = new Peer()
    peer.ws = new WebSocket(url)
    peer.ws.addEventListener('message', event => {
      const frame = JSON.parse(event.data)
      const waiter = peer.waiters.find(w => w.predicate(frame))
      if (waiter !== undefined) { peer.waiters.splice(peer.waiters.indexOf(waiter), 1); waiter.resolve(frame) }
      else peer.queue.push(frame)
    })
    await new Promise((resolve, reject) => {
      peer.ws.addEventListener('open', resolve, { once: true })
      peer.ws.addEventListener('error', () => reject(new Error('websocket failed')), { once: true })
    })
    return peer
  }
  send(type, payload) { this.ws.send(L.encodeControlFrame(L.createControlFrame(type, payload))) }
  next(predicate, label, timeoutMs = 4000) {
    const ready = this.queue.findIndex(predicate)
    if (ready >= 0) return Promise.resolve(this.queue.splice(ready, 1)[0])
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve }
      this.waiters.push(waiter)
      setTimeout(() => {
        const at = this.waiters.indexOf(waiter)
        if (at >= 0) { this.waiters.splice(at, 1); reject(new Error('timed out waiting for ' + label)) }
      }, timeoutMs)
    })
  }
  close() { try { this.ws.close() } catch {} }
}

async function linkPeers(server) {
  const hostPeer = await Peer.open(server.url)
  hostPeer.send('hello', { role: 'host', deviceId: hostDevice, identityKey: hostKeys.publicKey, accessToken, protocols: [PROTOCOL], capabilities: ['transport.relay'] })
  await hostPeer.next(f => f.type === 'hello.ack', 'host hello.ack')
  const clientPeer = await Peer.open(server.url)
  clientPeer.send('hello', { role: 'client', deviceId: phoneDevice, identityKey: phoneKeys.publicKey, accessToken, protocols: [PROTOCOL], capabilities: ['transport.relay'] })
  await clientPeer.next(f => f.type === 'hello.ack', 'client hello.ack')
  clientPeer.send('connect.request', { hostDeviceId: hostDevice })
  const incoming = await hostPeer.next(f => f.type === 'connect.incoming', 'connect.incoming')
  hostPeer.send('connect.accepted', { connectionId: incoming.payload.connectionId })
  await clientPeer.next(f => f.type === 'connect.accepted', 'connect.accepted')
  clientPeer.send('secure.handshake', { connectionId: incoming.payload.connectionId, targetDeviceId: hostDevice, step: 1, data: 'AAAA' })
  await hostPeer.next(f => f.type === 'secure.handshake', 'handshake step 1')
  hostPeer.send('secure.handshake', { connectionId: incoming.payload.connectionId, targetDeviceId: phoneDevice, step: 2, data: 'AAAA' })
  await clientPeer.next(f => f.type === 'secure.handshake', 'handshake step 2')
  return { hostPeer, clientPeer, connectionId: incoming.payload.connectionId }
}

async function rejectionCase(server, name, counters) {
  const { hostPeer, clientPeer, connectionId } = await linkPeers(server)
  const ciphertext = b64(Uint8Array.from({ length: 32 }, (_, i) => i + 1))
  const observed = []
  for (const counter of counters) {
    clientPeer.send('relay', { connectionId, targetDeviceId: hostDevice, counter, ciphertext })
    const outcome = await Promise.race([
      hostPeer.next(f => f.type === 'relay', 'relay at host', 2000).then(() => ({ forwarded: true })),
      clientPeer.next(f => f.type === 'error', 'error frame', 2000).then(error => ({ error })),
    ])
    observed.push({ counter, ...outcome })
    if (outcome.error !== undefined) break
  }
  hostPeer.close()
  clientPeer.close()
  return { name, counters, connectionId, observed }
}

const server = await Relay.startRelayServer({ maxNewDevicesPerHour: 1_000 })
const cases = []
cases.push(await rejectionCase(server, 'duplicate counter (same value twice)', [5, 5]))
cases.push(await rejectionCase(server, 'counter goes backwards', [5, 0]))
cases.push(await rejectionCase(server, 'counter is not a safe integer', [5, 1e21]))
await server.close()

writeFileSync(new URL('./rejections.json', import.meta.url), JSON.stringify({
  $comment: 'A real Relay Server, two real sockets, one bad counter. Every case is the second relay frame the phone sends on the same link.',
  source: {
    check: 'server/gateway.ts:278-284',
    reply: 'server/gateway.ts:153-159',
    catch: 'server/gateway.ts:198-211',
    note: 'the Server drops the link and sends the same error frame to both peers; the code is INVALID_MESSAGE for every case',
  },
  expected: {
    code: 'INVALID_MESSAGE',
    message: 'INVALID_MESSAGE',
    retryable: true,
    connectionId: '<the connectionId from connect.incoming>',
  },
  cases: cases.map(entry => ({
    name: entry.name,
    counters: entry.counters,
    result: entry.observed.map(step => step.error === undefined
      ? { counter: step.counter, forwardedToHost: true, error: null }
      : {
        counter: step.counter,
        forwardedToHost: false,
        error: {
          type: step.error.type,
          payload: {
            ...step.error.payload,
            connectionId: step.error.payload.connectionId === entry.connectionId
              ? '<the connectionId from connect.incoming>'
              : step.error.payload.connectionId,
          },
        },
      }),
  })),
}, null, 2) + '\n')

console.log('wrote keys.json, frames.json, fragments.json, rejections.json')
