/**
 * Keeps one link up: a single attempt at a time, retried with exponential
 * backoff, jitter and a ceiling. The phone wraps its connect() in this; the
 * computer's HostLink runs its own loop and is not built on it (yet).
 *
 * One line to wire (the attempt does the rest):
 *
 *     new LinkSupervisor({ attempt: openLinkAttempt }).start()
 *
 * The attempt resolves once the link is up and calls `closed()` when it goes
 * away; a thrown error is a failed attempt.
 */

export type SupervisorStatus = 'stopped' | 'connecting' | 'online' | 'offline'

export interface SupervisorAttempt {
  /** Aborted when the supervisor stops, or ends this attempt itself. */
  readonly signal: AbortSignal
  /** Call when the link this attempt opened has closed; the supervisor retries. */
  closed(reason?: unknown): void
}

export interface RetryPolicy {
  /** First wait after a failed or dropped attempt; default 1 000 ms. */
  minMs?: number
  /** Longest wait; default 60 000 ms. */
  maxMs?: number
  /** Each wait is this many times the last; default 2. */
  factor?: number
  /** Random spread of each wait, as a fraction of it; default 0.2 (0.8x–1.2x). */
  jitter?: number
  /** A link that stayed up this long resets the wait to minMs; default 10 000 ms. */
  stableMs?: number
}

export interface LinkSupervisorOptions {
  /** One connection attempt. Resolves when the link is up; rejects on failure. */
  attempt(context: SupervisorAttempt): Promise<void>
  onStatus?(status: SupervisorStatus): void
  /** Every failed attempt; the supervisor keeps retrying. */
  onError?(error: Error, attempt: number): void
  retry?: RetryPolicy
}

interface AttemptOutcome {
  online: boolean
  error?: Error
  /** How long the link stayed up before it closed; 0 when it never came up. */
  stableMs: number
}

const DEFAULT_RETRY: Required<RetryPolicy> = { minMs: 1_000, maxMs: 60_000, factor: 2, jitter: 0.2, stableMs: 10_000 }

export class LinkSupervisor {
  private readonly options: LinkSupervisorOptions
  private readonly retry: Required<RetryPolicy>
  private running = false
  private loopDone?: Promise<void>
  private wake?: () => void
  private controller?: AbortController
  private currentStatus: SupervisorStatus = 'stopped'
  private attempts = 0

  constructor(options: LinkSupervisorOptions) {
    this.options = options
    const retry = { ...DEFAULT_RETRY, ...options.retry }
    if (!(retry.minMs > 0) || !(retry.maxMs >= retry.minMs) || !(retry.factor >= 1) || !(retry.jitter >= 0) || !(retry.stableMs >= 0)) {
      throw new Error('The retry policy is invalid.')
    }
    this.retry = retry
  }

  get status(): SupervisorStatus { return this.currentStatus }

  /** Connection attempts started so far. */
  get attemptCount(): number { return this.attempts }

  start(): void {
    if (this.running) return
    this.running = true
    this.loopDone = this.loop()
  }

  async stop(): Promise<void> {
    if (!this.running) return
    this.running = false
    this.wake?.()
    this.controller?.abort()
    await this.loopDone
    this.loopDone = undefined
  }

  /** Leave the current wait and try again at once; a live link is left alone. */
  reconnect(): void {
    if (!this.running) return
    this.wake?.()
  }

  private setStatus(status: SupervisorStatus): void {
    if (status === this.currentStatus) return
    this.currentStatus = status
    this.options.onStatus?.(status)
  }

  private async loop(): Promise<void> {
    let delay = this.retry.minMs
    while (this.running) {
      const outcome = await this.attemptOnce()
      if (!this.running) break
      this.setStatus('offline')
      // A link that keeps dying young (a handshake that drops at once) must not
      // reset the wait, or it turns into a connect storm.
      if (outcome.online && outcome.stableMs >= this.retry.stableMs) delay = this.retry.minMs
      await this.wait(this.spread(delay))
      delay = Math.min(delay * this.retry.factor, this.retry.maxMs)
    }
    this.setStatus('stopped')
  }

  private attemptOnce(): Promise<AttemptOutcome> {
    return new Promise<AttemptOutcome>(resolve => {
      const controller = new AbortController()
      this.controller = controller
      let settled = false
      let online = false
      let onlineAt = 0
      const settle = (error?: Error): void => {
        if (settled) return
        settled = true
        if (this.controller === controller) this.controller = undefined
        controller.abort()
        resolve({ online, error, stableMs: onlineAt === 0 ? 0 : Date.now() - onlineAt })
      }
      controller.signal.addEventListener('abort', () => settle(new Error('The link attempt was stopped.')), { once: true })
      const context: SupervisorAttempt = { signal: controller.signal, closed: reason => settle(toError(reason)) }
      this.attempts += 1
      this.setStatus('connecting')
      let pending: Promise<void>
      try { pending = this.options.attempt(context) } catch (error) { settle(toError(error)); return }
      void pending.then(() => {
        if (settled) return
        online = true
        onlineAt = Date.now()
        this.setStatus('online')
      }, error => {
        settle(toError(error))
        this.options.onError?.(toError(error), this.attempts)
      })
    })
  }

  private spread(delayMs: number): number {
    const factor = 1 + (Math.random() * 2 - 1) * this.retry.jitter
    return Math.max(1, Math.round(delayMs * factor))
  }

  private wait(ms: number): Promise<void> {
    return new Promise<void>(resolve => {
      let timer: ReturnType<typeof setTimeout>
      const done = (): void => {
        clearTimeout(timer)
        if (this.wake === done) this.wake = undefined
        resolve()
      }
      timer = setTimeout(done, Math.max(1, ms))
      this.wake = done
    })
  }
}

function toError(reason: unknown): Error {
  return reason instanceof Error ? reason : new Error(typeof reason === 'string' && reason.length > 0 ? reason : 'The link attempt failed.')
}
