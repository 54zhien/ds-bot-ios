# DS Bot phone link — v1 protocol specification

This is the acceptance basis for the Swift port (N0 in
`plans/2026-11-16-native-rewrite.md`). The TypeScript implementation under `link/`
is the reference: where this document and the code disagree, the code wins and
this file is the bug. Every claim carries a `file:line`.

A Swift implementation conforms when (a) it reproduces
`link-test-vectors/` byte for byte and (b) it completes the interop walkthrough
in §12.

## 0. Constants

| Name | Value | Source |
|---|---|---|
| protocol version | 1 | `link/src/frames.ts:1` |
| WebSocket path | `/v1/link` | `link/src/frames.ts:3` |
| max control frame | 65536 bytes | `link/src/frames.ts:4` |
| max relay frame | 1048576 bytes | `link/src/frames.ts:5` |
| fragment chunk | 49152 bytes | `link/src/frames.ts:6` |
| max message | 4194304 bytes | `link/src/frames.ts:7` |
| fragment header | 17 bytes | `link/src/frames.ts:11` |
| fragments in flight | 8 | `link/src/frames.ts:12` |
| server heartbeat | 25 s | `link/server/gateway.ts:53` |
| server peer timeout | 3 heartbeats (75 s) | `link/server/gateway.ts:138` |
| host silence timeout | 75 s | `link/src/host.ts:72` |
| host tunnels | 16 | `link/src/host.ts:300` |
| calls per tunnel | 32 | `link/src/host.ts:70` |
| pending emits per tunnel | 64 | `link/src/host.ts:71` |
| RPC timeout (default) | 30 s | `link/src/rpc-client.ts:46` |
| retry backoff | 1 s → 60 s, ×2, ±20% | `link/src/supervisor.ts:52` |

## 1. Transport and envelopes

**Transport.** One WebSocket per device to the Relay Server. Text frames only:
the Server rejects a binary frame (`link/server/gateway.ts:186`) and the host
rejects one the same way (`link/src/host.ts:224`). Every text frame is one JSON
object.

**Control frame.** `{v, id, type, timestamp, payload}` (`link/src/frames.ts:32-38`).
`v` must equal 1, `id` a non-empty string, `timestamp` a number, `payload` an
object (`link/src/frames.ts:199-207`). Valid types (`link/src/frames.ts:14-27`):
`hello`, `hello.ack`, `connect.request`, `connect.incoming`, `connect.accepted`,
`connect.rejected`, `secure.handshake`, `relay`, `ping`, `pong`, `error`.

**Remote message** (inside the encrypted channel). `{v, id, type, timestamp, payload}`
with `type` in `rpc.request`, `rpc.response`, `rpc.error`, `event`
(`link/src/frames.ts:29-30`, `106-112`).

**Size limits.** A frame is checked against `maxRelayFrameBytes` when `type` is
`relay` and against `maxControlFrameBytes` otherwise; a peer may only lower the
limit the Server announced, never raise it (`link/src/frames.ts:308-314`). Decode
rejects anything above 1 MiB before parsing (`link/src/frames.ts:172`).

**base64url.** No padding, `-` and `_` instead of `+` and `/`; decoding accepts
padding (`link/src/keys.ts:37-46`). Every byte string on the wire — keys, tokens,
handshake data, ciphertext — uses it.

**JSON is not canonical.** Decoders must ignore unknown fields and must not depend
on field order; our encoders emit `v, id, type, timestamp, payload` in that order,
which matters only for byte-exact comparison against the vectors.

## 2. Identity and pairing

- Each device has one X25519 key pair, 32-byte private key, base64url on the wire
  (`link/src/keys.ts:10-17`).
- Device id: `d-` + base64url(sha256(publicKey) first 16 bytes)
  (`link/src/keys.ts:27-31`). The Server recomputes it from `hello.identityKey`
  and rejects a mismatch (`link/server/gateway.ts:224-226`).
- Access token: 32 random bytes, base64url; the Server accepts 32-256 characters
  (`link/server/gateway.ts:219`) and stores only its SHA-256
  (`link/server/store.ts:92-99`). A device claims its id with its first token and
  must bring the same token afterwards (`link/server/store.ts:57-73`).
- Pairing QR: `dsbot://pair?v=1&server=…&host=…&key=…&code=…&name=…`
  (`link/src/pairing.ts:55-65`). `server` must be `ws:` or `wss:`, and `host` must
  equal `deviceIdFor(key)` (`link/src/pairing.ts:78-86`).
- The phone sends the pairing code only inside the Noise handshake (`link/src/pairing.ts:4-7`,
  `link/src/secure-transport.ts:64`), so the Server never sees it.
- On the computer a code is single-use, lives 5 minutes, and closes after 5 wrong
  attempts (`link/src/pairing.ts:114-145`). A paired device is re-authorised by
  its key, not by the code (`link/src/pairing.ts:132-145`).

## 3. Connection sequence

Phone = initiator, computer = responder. The Server is a switchboard; it never
reads payloads.

| # | Direction | Frame | Payload |
|---|---|---|---|
| 1 | both → Server | `hello` | `role`, `deviceId`, `identityKey`, `accessToken`, `protocols`, `capabilities` (`link/src/frames.ts:45-53`) |
| 2 | Server → both | `hello.ack` | `protocol`, `serverVersion`, `connectionSessionId`, `heartbeatIntervalMs`, `maxControlFrameBytes`, `maxRelayFrameBytes`, `capabilities` (`link/src/frames.ts:55-63`, `gateway.ts:233-241`) |
| 3 | phone → Server | `connect.request` | `hostDeviceId` |
| 4 | Server → computer | `connect.incoming` | `connectionId`, `clientDeviceId`, `clientIdentityKey` (`link/server/gateway.ts:305-309`) |
| 5 | computer → Server | `connect.accepted` | `connectionId` |
| 6 | phone → computer | `secure.handshake` step 1 | `connectionId`, `targetDeviceId`, `step`, `data` (base64url) |
| 7 | computer → phone | `secure.handshake` step 2 | same shape |
| 8 | both ways | `relay` | `connectionId`, `targetDeviceId`, `counter`, `ciphertext` |

Server-side link stages: `pending` → `accepted` → `handshake` → `ready`
(`link/server/gateway.ts:28-35`, `245-289`). A link that is not `ready` within
30 s is dropped (`link/server/gateway.ts:143`); a socket that never sends `hello`
is terminated after 5 s (`link/server/gateway.ts:173`). If the computer is not
connected the Server answers `HOST_OFFLINE` with `retryable: true` and keeps the
phone's socket open (`link/server/gateway.ts:291-296`).

The Server replaces an older socket from the same device id with
`CONNECTION_REPLACED` (`link/server/gateway.ts:230`), so one device may hold only
one control socket.

## 4. Noise IK

**Suite.** `Noise_IK_25519_ChaChaPoly_SHA256` (`link/src/noise.ts:11`), role
`initiator` on the phone, `responder` on the computer.

**Prologue** (`link/src/noise.ts:127-134`), UTF-8, NUL-separated, written ␀ for
the NUL byte here:

```
DS-BOT-LINK␀v=1␀connection=<connectionId>␀host=<hostDeviceId>␀client=<clientDeviceId>
```

With the vector values this is 102 bytes and its hex is in `keys.json`.

**Message framing.** Standard IK (`link/node_modules/@lukeburns/clatterjs`
`nqHandshake.js:315-367`):

| Message | Layout | Vector length |
|---|---|---|
| 1 (initiator) | `e` 32 B ‖ `s` encrypted 48 B ‖ payload encrypted (payload + 16 B tag) | 121 B for a 25-byte hello |
| 2 (responder) | `e` 32 B ‖ payload encrypted (payload + 16 B tag) | 72 B for a 24-byte hello |

The decrypted payload is the handshake hello, JSON, `{name?, pairingCode?}` with
`name` ≤ 64 and `pairingCode` ≤ 128 characters (`link/src/pairing.ts:20-53`). An
empty `data` decrypts to an empty hello, which is legal (`link/src/pairing.ts:33-36`).

**State.** `writeHandshake` and `readHandshake` alternate; calling either out of
turn raises `NOISE_HANDSHAKE_ORDER`, encrypting before completion raises
`NOISE_NOT_READY` (`link/src/noise.ts:104-115`). The responder verifies the
initiator's static key against the paired key and fails with
`PEER_IDENTITY_MISMATCH` (`link/src/noise.ts:96-102`).

**Session keys.** After message 2 the transport has two ChaChaPoly keys: what the
initiator sends and what the responder sends — `initiatorToResponder` and
`responderToInitiator` in `keys.json` (`link/src/noise.ts:90-94`). Both sides also
agree on a 32-byte handshake hash (`keys.json`, `handshakeHash`). A standard IK
implementation derives the same values; the vector
publishes them so the Swift side can assert on them directly.

**Transport messages.** `ciphertext = plaintext ‖ 16-byte tag`, empty associated
data, nonce starts at 0 and increments by one per message in each direction
(`link/src/noise.ts:70-76`). No rekey is used during a link.

**Handshake timeout.** The phone gives the responder 10 s (`link/src/secure-transport.ts:64`).

## 5. Relay frames and counters

`relay` payload: `{connectionId, targetDeviceId, counter, ciphertext}`
(`link/src/frames.ts:92-97`). `ciphertext` is base64url of one Noise message.

**Counter rules (server).** Accepted only when the link is `ready`, `counter` is
a safe integer, and it is strictly greater than the last value seen from that
sender on that link (`link/server/gateway.ts:278-284`). The counter is forwarded
untouched (`link/server/gateway.ts:288`).

**Counter rules (computer).** The same check again, per tunnel
(`link/src/host.ts:349-358`).

**Counter rules (phone).** Starts at 0 for each link and increments by one per
`relay` frame (`link/src/relay-transport.ts:168-180`).

Strictly increasing, **not** contiguous: a gap is legal and nothing retransmits
(§13 lists this as an implementation detail, not a promise). A rejected counter
drops the link and sends `INVALID_MESSAGE` to both peers
(`link/server/gateway.ts:153-159`, `198-211`); `link-test-vectors/rejections.json`
records the exact frames.

Counters are per link, reset whenever a new `connectionId` is issued — not per
device and not per socket.

## 6. Application messages

Inside the encrypted channel (`link/src/frames.ts:114-136`):

- `rpc.request` `{method, params}` — `method` non-empty, `params` free-form.
- `rpc.response` `{requestId, result}`.
- `rpc.error` `{requestId, code, message, details?, retryable?}`.
- `event` `{event, data, seq?}` — `seq` exists but is never set
  (`link/src/host.ts:153-166`); there is no replay.

**Request id** is a UUID v4 (`link/src/frames.ts:316-318`) and the reply echoes it.

**Computer side.** A request is deduplicated by id within its tunnel
(`link/src/host.ts:361`), at most 32 run at once (`link/src/host.ts:367-368`), and
the reply is sent exactly once (`link/src/host.ts:381-384`). A request whose
handler is still running when the tunnel closes is aborted
(`link/src/host.ts:407-413`).

**Phone side.** A call is sent once and never retried; a timeout rejects it
locally with `RPC_TIMEOUT` (`link/src/rpc-client.ts:32-35`, `67-98`). Closing the
link rejects every pending call with `TRANSPORT_CLOSED`
(`link/src/rpc-client.ts:124-127`).

**No cancellation.** There is no `rpc.cancel` (`link/src/frames.ts:29`); aborting
locally only rejects the local promise.

## 7. Fragmentation

Applied to the application message **before** encryption, so the receiver joins
fragments before it sees the message (`link/src/secure-transport.ts:124-132`,
`link/src/frames.ts:224-247`).

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `DSBF` (0x44 0x53 0x42 0x46) |
| 4 | 1 | version, 1 |
| 5 | 4 | `messageId`, big-endian u32, never 0 |
| 9 | 2 | `index`, big-endian u16 |
| 11 | 2 | `total`, big-endian u16 |
| 13 | 4 | `totalBytes`, big-endian u32 |
| 17 | n | chunk, at most 49152 bytes |

- A message of 49152 bytes or less is sent as one frame with no header
  (`link/src/frames.ts:226`).
- A larger message splits into `ceil(totalBytes / 49152)` fragments
  (`link/src/frames.ts:230`); the last one is short.
- `messageId` starts at 1 per codec instance and wraps to 1 after 0xffffffff
  (`link/src/frames.ts:228-229`).
- Reassembly accepts only index 0 first, then consecutive indices, at most 8
  partial messages, `total == ceil(totalBytes / 49152)`, `totalBytes ≤ 4 MiB`;
  anything else is an error and, at the transport layer, closes the link
  (`link/src/frames.ts:259-292`).
- Each fragment is encrypted separately (one Noise message, one nonce) and sent as
  its own `relay` frame with its own counter.

The codec is used in both directions (`link/src/secure-transport.ts:27-28`), so a
reply larger than 48 KiB fragments too.

## 8. Heartbeat and watchdog

**Server.** Every 25 s it sends `ping {nonce}` to every peer
(`link/server/gateway.ts:53`, `135-145`); a `pong` must echo the nonce
(`link/server/gateway.ts:247-251`). A peer silent for three intervals (75 s) is
disconnected with `CONNECTION_FAILED` (`link/server/gateway.ts:138`). The interval
is announced in `hello.ack.heartbeatIntervalMs` (`link/src/frames.ts:59`,
`link/server/gateway.ts:237`).

**Phone.** The silence threshold is the interval the Server announced, or 15 s
when it announced none (`link/src/relay-transport.ts:228-232`). One probe waits
10 s, then one retry, then the link is declared dead — silence + 2 × 10 s, about
45 s against this Server (`link/src/relay-transport.ts:150-164`, `234-241`). An
idle link is probed no faster than every silence + 10 s
(`link/src/relay-transport.ts:159-163`), and only one probe may be outstanding
(`link/src/relay-transport.ts:208-215`). Any inbound frame clears the probe.

**Computer.** Its own socket is closed after 75 s of silence
(`link/src/host.ts:72`, `208-210`).

A reverse proxy between phone and Server must allow more than 25 s of silence
(`link-deployment.md` §5).

## 9. Reconnect

**Phone (supervisor).** One attempt at a time; wait 1 s, then ×2 to 60 s, each
wait spread by ±20%; the wait resets to 1 s only after a link stayed up 10 s
(`link/src/supervisor.ts:52`, `105-115`, `152-154`). Anything shorter than that —
a handshake that drops immediately — keeps backing off, which is what stops a
connect storm.

**Computer.** Its own loop: 1 s → 60 s with 0.8-1.2 jitter, reset as soon as the
Server answered `hello.ack` (`link/src/host.ts:176-198`).

**No resume.** A reconnect is a new socket, a new `connectionId`, a new Noise
handshake and counters back to 0. Calls in flight fail and are not resent
(`link/src/rpc-client.ts:124-127`). Events emitted while the link was down are
lost (`link/src/host.ts:153-166`).

## 10. Error codes

Codes carried in `error` (control frame) or `connect.rejected` are strings; the
receiver treats an unknown code as a permanent error.

| Code | Raised by | Meaning | Receiver action |
|---|---|---|---|
| `AUTH_REQUIRED` | Server `gateway.ts:216` | first frame was not `hello` | reconnect |
| `AUTH_INVALID` | Server `gateway.ts:218-226`, `store.ts:61-63` | id/key/token mismatch | fix pairing, do not retry blindly |
| `UNSUPPORTED_VERSION` | Server `gateway.ts:227` | no shared version | upgrade the app |
| `RATE_LIMITED` | Server `gateway.ts:123`, `189`, `302` | too many devices / frames / links | back off |
| `SERVER_FULL` | Server `store.ts:68` | device table full | contact the operator |
| `INVALID_MESSAGE` | Server `gateway.ts:259-287`, host `host.ts:299`, `327`, `350` | malformed frame, wrong stage, bad counter | link is dropped; reconnect |
| `CONNECTION_NOT_FOUND` | Server `gateway.ts:254` | frame for a link this peer is not in | ignore, drop the link |
| `CONNECTION_FAILED` | Server `gateway.ts:257` | the other peer vanished | reconnect |
| `CONNECTION_REPLACED` | Server `gateway.ts:230` | a newer socket claimed this device id | stop; another instance owns it |
| `SLOW_CONSUMER` | Server `gateway.ts:149` | 4 MiB of unsent data | reconnect, lower the payload |
| `CAPABILITY_NOT_SUPPORTED` | Server `gateway.ts:298-300` | no `transport.relay` on one side | upgrade |
| `HOST_OFFLINE` | Server `gateway.ts:295` | computer not connected | retry (retryable: true) |
| `NOT_PAIRED` | Host `host.ts:301`, `334` | key not in the registry, or bad code | pair again |
| `HOST_BUSY` | Host `host.ts:300` | 16 tunnels already | wait |
| `HANDSHAKE_FAILED` | Host `host.ts:345` | Noise step failed | reconnect |
| `DEVICE_REVOKED` | Host `host.ts:149` | the user removed the phone | stop, re-pair |
| `SEND_FAILED` | Host `host.ts:159`, `163`, `384` | a send did not complete | reconnect |
| `RPC_TIMEOUT` | Phone `rpc-client.ts:12` | no reply in time | retry at the app layer |
| `RPC_ABORTED` | Phone `rpc-client.ts:169-171` | the caller aborted | nothing |
| `TRANSPORT_CLOSED` | Phone `rpc-client.ts:124-127` | link closed | reconnect, resend by hand |
| `CLIENT_CLOSED` | Phone `rpc-client.ts:114-122` | the app closed the client | nothing |
| `SERVER_UNREACHABLE` | Phone `relay-transport.ts:87`, `137`, `145`, `156` | DNS/TCP/TLS/handshake failed, or the Server went silent | back off, retry |
| `NOISE_*`, `PEER_IDENTITY_MISMATCH`, `INVALID_KEY` | Phone `noise.ts:104-115`, `117-124`, `136-140` | local Noise failures | programming or pairing error |
| `INVALID_REQUEST` | Host `host.ts:366` | empty method | fix the call |
| `HOST_ERROR` | Host `host.ts:376-377` | the handler threw | show the message |

`retryable` in an `error` payload is advisory: the phone's transport treats every
`error` frame as fatal for the current socket (`link/src/relay-transport.ts:241-245`).

## 11. Test vectors

`link-test-vectors/` holds JSON produced by `generate.mjs` from the code above:
`keys.json` (handshake bytes, session keys, first transport message),
`frames.json` (`hello`, `relay`, `error` encoded), `fragments.json` (4 KiB and
100 KiB messages), `rejections.json` (counter rules, captured from a real Server).
See `link-test-vectors/README.md` for how to compare and how to regenerate.

## 12. Interop walkthrough

Goal: a Swift client pairs, handshakes and makes one RPC call against the real
Node components.

**1. Start the Relay Server** (from the repository root):

```sh
cd link && npm ci
PORT=8787 DSBOT_LINK_DATA=./data/devices.json node server/main.ts
```

Expected: one line, `DS Bot link Server: ws://0.0.0.0:8787/v1/link` — that is all
the Server ever logs (`link/server/main.ts:18`). Liveness: `curl -sS
http://127.0.0.1:8787/healthz` → `ok`.

**2. Start a stand-in computer.** Save this as `docs/host.mjs` and run
`node docs/host.mjs`:

```js
import { DeviceRegistry, HostLink, deviceIdFor, generateKeyPair, pairingUri, randomToken } from '../link/src/index.ts'

const keys = generateKeyPair()
const identity = { deviceId: deviceIdFor(keys.publicKey), ...keys }
const registry = new DeviceRegistry()
const host = new HostLink({
  url: 'ws://127.0.0.1:8787/v1/link',
  identity,
  accessToken: randomToken(),
  name: 'Desk',
  admits: (id, key) => registry.admits(id, key),
  authorize: (id, key, hello) => registry.authorize(id, key, hello),
  handle: async (method, params) => ({ echoed: method, params }),
  onStatus: status => console.log('host', status),
  onReadyCount: count => console.log('phones ready:', count),
})
host.start()
await host.waitOnline()
const { code } = registry.openPairing()
console.log('pair:', pairingUri({ server: 'ws://127.0.0.1:8787/v1/link', hostDeviceId: identity.deviceId, hostKey: identity.publicKey, code, name: 'Desk' }))
```

Expected output: `host connecting`, `host online`, then one `pair: dsbot://pair?…`
line. The `HostLink` has no logging of its own; those lines come from the two
callbacks and the final `console.log`.

**3. Pair and connect from the Swift side.** Decode the `pair:` URI, connect to
`ws://127.0.0.1:8787/v1/link`, send `hello` with `role: "client"` and the phone's
own key, send `connect.request` with `hostDeviceId` from the URI, answer
`connect.incoming` by waiting for `connect.accepted`, then run the Noise
handshake (§4) with the pairing code inside the encrypted hello. On success the
host prints `phones ready: 1`.

**4. Call once.** Send `rpc.request` `{method: "bot", params: {op: "state"}}`
inside the encrypted channel. The stand-in computer answers
`{echoed: "bot", params: {"op": "state"}}` in an `rpc.response` with the same
request id.

**5. Confirm on the computer side.** `/var/lib/dsbot-link/devices.json` (or
`./data/devices.json`) now contains the phone's device id, and the host printed
the ready count. There is no per-device log — do not wait for one
(`link-deploy-runbook.md` §6).

If step 4 hangs: check the counter (must be strictly increasing from 0), the
`connectionId` inside the `relay` payload, and that the Noise session is complete
before the first `relay` frame.

## 13. Implementation-defined — may change without a version bump

Treat these as behaviour of the current implementation, not as promises. A Swift
port should match them today and expect them to move:

- counters must be strictly increasing but need not be contiguous (§5);
- the exact JSON field order our encoders emit — parsers must ignore order;
- the `id` format (UUID v4 today);
- the fragment `messageId` start value and wrap;
- the phone's probe cadence floor of silence + probe timeout;
- the 15 s fallback silence when a Server sends no heartbeat interval;
- `retryable` semantics (the phone treats every `error` frame as fatal);
- supervisor and host backoff constants;
- the `capabilities` strings — only `transport.relay` is required today;
- error `message` text (codes are the contract, text is not).

## 14. Not covered, or unverified

- **Cancellation and event replay** do not exist (§6). This is a product gap, not
  a spec gap; do not invent them in the port without a protocol change agreed
  with the Server first.
- **iOS TLS trust** and system proxy behaviour are platform facts, not covered by
  any test in this repository (`link-deployment.md`).
- **Android** is out of scope.
- **Cross-implementation Noise interop** is verified for the TS code by its own
  tests; whether Swift's CryptoKit-based IK reproduces `keys.json` is exactly what
  N0 has to show — this document asserts the vectors, not the outcome.
