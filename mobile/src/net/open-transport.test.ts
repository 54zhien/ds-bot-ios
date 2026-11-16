import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openTransport, type LinkTarget } from './supervised.ts'

const target: LinkTarget = {
  server: 'ws://127.0.0.1:9',
  deviceId: 'd-phone',
  identityKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  privateKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  accessToken: 'token',
  hostDeviceId: 'd-computer',
  hostKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  name: 'iPhone',
}

// An older caller dropped the field; the phone must say so instead of failing
// inside the Noise handshake with a TypeError.
test('openTransport refuses a target with no private key', async () => {
  const withoutKey = { ...target, privateKey: undefined as unknown as string }
  await assert.rejects(
    openTransport(withoutKey),
    (error: Error) => !(error instanceof TypeError) && /no private key/.test(error.message),
  )
})
