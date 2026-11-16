import { LinkSupervisor, RelayTransport, RpcClient, SecureTransport, type SupervisorStatus } from '../../../link/src/index.ts'

// No react-native here on purpose: node --test loads this file through Node's
// type stripping, which cannot resolve a bare react-native import. Everything the
// phone must supply (its name, the keys) comes in as arguments.

export interface LinkTarget {
  server: string
  deviceId: string
  identityKey: string
  accessToken: string
  hostDeviceId: string
  hostKey: string
  /** The phone's name, shown on the computer. */
  name: string
}

export async function openTransport(target: LinkTarget, pairingCode?: string): Promise<RpcClient> {
  const relay = new RelayTransport(target.server, {
    deviceId: target.deviceId,
    identityKey: target.identityKey,
    accessToken: target.accessToken,
    targetDeviceId: target.hostDeviceId,
  })
  const secure = new SecureTransport(relay, { deviceId: target.deviceId, publicKey: target.identityKey, accessToken: target.accessToken } as never, { deviceId: target.hostDeviceId, identityKey: target.hostKey }, {
    hello: { name: target.name, ...(pairingCode === undefined ? {} : { pairingCode }) },
  })
  const client = new RpcClient(secure)
  await client.connect()
  return client
}

export interface SupervisedLink {
  start(): void
  stop(): Promise<void>
  reconnect(): void
  readonly status: SupervisorStatus
}

/** One attempt = one open plus the caller's handshake; every wait belongs to the supervisor. */
export function connectSupervised({ target, pairingCode, onStatus, onOpen, onError }: {
  target: LinkTarget
  pairingCode?: string
  onStatus?: (status: SupervisorStatus) => void
  onOpen: (client: RpcClient) => boolean | Promise<boolean>
  onError?: (error: Error) => void
}): SupervisedLink {
  let current: RpcClient | undefined
  const supervisor = new LinkSupervisor({
    attempt: async ({ signal, closed }) => {
      const client = await openTransport(target, pairingCode)
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
