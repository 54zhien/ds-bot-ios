import { LinkSupervisor, RelayTransport, RpcClient, SecureTransport, type SupervisorStatus } from '../../../link/src/index.ts'

// No react-native here on purpose: node --test loads this file through Node's
// type stripping, which cannot resolve a bare react-native import. Everything the
// phone must supply (its name, the keys) comes in as arguments.

export interface LinkTarget {
  server: string
  deviceId: string
  identityKey: string
  /** Never leaves the phone: it keys the Noise handshake for this device. */
  privateKey: string
  accessToken: string
  hostDeviceId: string
  hostKey: string
  /** The phone's name, shown on the computer. */
  name: string
}

export async function openTransport(target: LinkTarget, pairingCode?: string): Promise<RpcClient> {
  if (typeof target.privateKey !== 'string' || target.privateKey.length === 0) {
    throw new Error('The link target has no private key, so the phone cannot open the encrypted link.')
  }
  const relay = new RelayTransport(target.server, {
    deviceId: target.deviceId,
    identityKey: target.identityKey,
    accessToken: target.accessToken,
    targetDeviceId: target.hostDeviceId,
  })
  const secure = new SecureTransport(relay, { deviceId: target.deviceId, publicKey: target.identityKey, privateKey: target.privateKey }, { deviceId: target.hostDeviceId, identityKey: target.hostKey }, {
    hello: { name: target.name, ...(pairingCode === undefined ? {} : { pairingCode }) },
  })
  const client = new RpcClient(secure)
  await client.connect()
  return client
}

export type { SupervisorStatus } from '../../../link/src/index.ts'

export interface SupervisedLink {
  start(): void
  stop(): Promise<void>
  reconnect(): void
  readonly status: SupervisorStatus
}

/** One attempt = one open plus the caller's handshake; every wait belongs to the supervisor. */
export function connectSupervised({ target, pairingCode, open, onStatus, onOpen, onError }: {
  target?: LinkTarget
  pairingCode?: string
  /** Opens the link itself, for callers that already hold the phone's fields. */
  open?: () => Promise<RpcClient>
  onStatus?: (status: SupervisorStatus) => void
  onOpen: (client: RpcClient) => boolean | Promise<boolean>
  onError?: (error: Error) => void
}): SupervisedLink {
  const openLink = open ?? (target === undefined ? undefined : () => openTransport(target, pairingCode))
  if (openLink === undefined) throw new Error('connectSupervised needs a target or an open function.')
  let current: RpcClient | undefined
  const supervisor = new LinkSupervisor({
    attempt: async ({ signal, closed }) => {
      const client = await openLink()
      if (signal.aborted) { await client.close(); throw new Error('The link attempt was stopped.') }
      current = client
      client.onClose(() => { if (current === client) current = undefined; closed() })
      signal.addEventListener('abort', () => void client.close(), { once: true })
      const usable = await onOpen(client)
      if (!usable) { current = undefined; await client.close(); throw new Error('The computer needs a newer DS Bot.') }
    },
    onStatus,
    onError: error => onError?.(error),
  })
  return { start: () => supervisor.start(), stop: () => supervisor.stop(), reconnect: () => supervisor.reconnect(), get status() { return supervisor.status } }
}
