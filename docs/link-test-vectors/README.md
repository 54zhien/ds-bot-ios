# link test vectors

Machine-readable vectors for the Swift port of the DS Bot phone link. Every byte
here is produced by the TypeScript implementation under `link/`, never by hand:
`generate.mjs` calls the shipped code and writes the four JSON files.

The protocol prose is in `../link-protocol-spec.md`.

## Regenerate

```sh
cd link && npm ci          # once
node ../docs/link-test-vectors/generate.mjs
```

Node 24 is required (the Server and the vectors import `.ts` directly).

The output is deterministic: the handshake uses a pinned RNG
(`sha256(tag || uint24le(n))`), every frame uses a fixed timestamp
(`1893456000000`), and nothing reads the clock. To prove it, run the generator
twice and compare hashes:

```sh
node generate.mjs && sha256sum *.json
node generate.mjs && sha256sum *.json   # identical
```

## Files

| File | What a Swift test should do with it |
|---|---|
| `keys.json` | Handshake bytes. Feed the fixed X25519 keys and the pinned RNG into your Noise IK implementation; `handshake.message1.hex` and `message2.hex` must match byte for byte, then `session.initiatorToResponder` / `responderToInitiator` (32-byte keys), `handshake.handshakeHash.hex` and `transportProof.ciphertextHex` must match too. |
| `frames.json` | Envelope encoding. Parse each `frames[].decoded` and re-encode it: `frames[].encoded` is the exact string to produce. Covers `hello`, `relay` and `error`. |
| `fragments.json` | Chunking. `small` (4 KiB) is below the 48 KiB chunk, so there is no DSBF header and `fragments` is empty. `large` (100 KiB) splits into three fragments; each entry gives the 17-byte header fields, the transport nonce, the relay counter and `wireFrameJson` (the full frame the Server would see). |
| `rejections.json` | Counter rules. Produced by a real Server: a duplicate counter, a counter that goes backwards, and a non-safe-integer counter each get the same `error` frame, and the link is dropped. |

`keys.json` and `fragments.json` share one handshake transcript. `fragments.json`
uses a fresh copy of it, so its transport nonces start at 0 again.

## Comparing

- `ciphertextHex` is lowercase hex of the raw Noise ciphertext (plaintext +
  16-byte Poly1305 tag).
- `wireFrameJson` is the exact WebSocket text frame; `payload.ciphertext` inside
  it is base64url without padding.
- Hex is omitted for frames above 8 KiB so the file stays readable; decode
  `payload.ciphertext` instead.
- `plaintextPattern`: `byte(i) = (i * 37 + 11) & 0xff`. Rebuild the plaintext
  from the index, do not store it.

## Where the numbers come from

| Constant | Value | Source |
|---|---|---|
| chunk | 49152 | `link/src/frames.ts:6` |
| max message | 4194304 | `link/src/frames.ts:7` |
| fragment header | 17 bytes | `link/src/frames.ts:11` |
| max control frame | 65536 | `link/src/frames.ts:4` |
| max relay frame | 1048576 | `link/src/frames.ts:5` |

If the vectors and the code ever disagree, the code wins: regenerate and fix
the vectors, not the other way round.
