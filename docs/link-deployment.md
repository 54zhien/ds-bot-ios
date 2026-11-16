# Deploying the DS Bot link

How to run the Relay Server (`link/server/`) for phones and computers behind
restricted networks, and how to tell what a network is doing to it. Every claim
points at the code that fixes it; anything not covered by a test in this
repository is marked **unverified**.

The relay forwards `relay` frames whose payload is Noise ciphertext
(`link/src/frames.ts:92-97`, `link/src/noise.ts:11`): it sees device ids, sizes
and timing, never message content. That shapes everything below — a private
network can use plain `ws://`, anything on the open Internet should be `wss://`.

## 1. Standard deployment

| Piece | Value | Where |
|---|---|---|
| Bind | `HOST`/`PORT`, default `0.0.0.0:8787` | `server/main.ts:8-9` |
| Protocol | plain `ws://` only; TLS is not in the Server | `server/server.ts:48` |
| Path | exactly `/v1/link`; anything else is answered 404 | `server/server.ts:34-40`, `src/frames.ts:3` |
| Liveness | `GET /healthz` answers `200 ok` | `server/server.ts:27-33` |
| Devices | `DSBOT_LINK_DATA`; memory only when unset | `server/main.ts:10`, `README.md:28` |

- A public hostname with a CA-issued certificate (Let's Encrypt is fine). A
  self-signed certificate fails on the phone: the WebSocket runs on the
  platform TLS stack, which does not trust a private CA unless it was installed
  on the device (**unverified in this repository** — no test covers TLS trust).
- The proxy must forward the upgrade and speak HTTP/1.1 to the Server. This
  probe must answer `101`:

```sh
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://link.example.com/v1/link
```

HTTP/2 and HTTP/1.1: the edge may serve h2 for ordinary HTTPS, but a WebSocket
upgrade is HTTP/1.1 (RFC 6455) and both clients open one
(`src/relay-transport.ts:77`, `src/host.ts:205`). WebSocket over h2 (RFC 8441)
is not used. An edge that only speaks h2 to the upstream (gRPC-style gateways)
breaks the link, so configure `proxy_http_version 1.1`.

Sizing: one computer socket carries every phone it has, at most 16 tunnels
(`src/host.ts:300`). Per socket the Server allows 512 frames/s and 16 MiB/s
(`server/gateway.ts:189`) and cuts a peer whose send buffer passes 4 MiB
(`server/gateway.ts:149`).

## 2. Diagnosing a restricted network

| Symptom | Likely cause | How to confirm |
|---|---|---|
| The computer never reaches `online`; the phone retries for a minute, then reports "not connected" | DNS pollution, or the name does not resolve | `nslookup <host>` on that network against a resolver you trust; compare addresses |
| TCP connects, TLS dies right after ClientHello | SNI-based filtering, or a forced TLS intermediary | `curl -v https://<host>/healthz`; a reset after ClientHello, or a certificate issuer that is not yours |
| Certificate error mid-handshake | Missing intermediate, TLS version too old, or an interception CA | `curl -v` prints the chain; a device will not trust an unknown root (**unverified on device**) |
| `404` / `400` / `426` instead of `101` | Wrong path, or the proxy does not forward `Upgrade` | the `curl` probe in §1; a `404` specifically means the request missed `/v1/link` (`server/server.ts:35-38`) |
| `101`, then silence | Response buffering on, or the upstream is not HTTP/1.1 | `proxy_buffering off`, `proxy_http_version 1.1` |
| Works, then drops on a fixed interval | NAT mapping timeout, or a proxy read timeout shorter than the heartbeat | see the timing below |
| Drops with `SLOW_CONSUMER` | A peer cannot drain 4 MiB of buffer | `server/gateway.ts:149`; look at that peer's network |
| The phone loops with `SERVER_UNREACHABLE` | The phone's own watchdog fired on a half-open socket | `closeReason` on the client (`src/relay-transport.ts:48-49`) |

Timing, so a scheduled drop can be told apart from a bug:

- The Server pings every 25 s (`server/gateway.ts:53`, `135-145`) and drops a
  peer that has not ponged for three intervals, 75 s (`server/gateway.ts:138`).
- The phone's silence threshold is the interval the Server states in
  `hello.ack` (`src/frames.ts:59`, read at `src/relay-transport.ts:262-270`);
  it falls back to 15 s only when a Server states none
  (`src/relay-transport.ts:228-232`). One probe waits 10 s
  (`234-237`); a silent link gets one retry and dies on the second miss, so
  silence + 2 × 10 s ≈ 45 s against this Server (`150-164`, `239-241`).
- The computer closes a socket that has been silent for 75 s
  (`src/host.ts:72`, `208-210`).
- Any proxy read timeout must therefore exceed 25 s; 60–90 s is safe. A drop
  that lands exactly on the proxy's own timeout is the proxy, not the link.

Older Servers: a Server that omits `heartbeatIntervalMs` in `hello.ack` leaves
the phone on the fixed 15 s silence window.

## 3. Networks that only allow 80/443

The link already passes: it is one TLS session on 443 to a hostname, which is
what an HTTPS-only network permits. Nothing listens on plain 80 and nothing
should — the Server's `ws://` listener is for a private network or a TLS proxy
in front of it (`server/server.ts:48`).

What still stops it:

- Allow-lists by SNI or hostname: only names the policy knows pass. Nothing here
  works around that.
- TLS interception with a private CA: the device rejects the chain
  (**unverified on device**).
- Proxy authentication: the clients open a WebSocket directly
  (`src/relay-transport.ts:77`, `src/host.ts:205`) and implement no HTTP CONNECT
  authentication (**unverified on iOS/desktop**).
- Captive portals: the portal answers instead of the relay, so pairing and the
  link fail until the network is authenticated.

## 4. When UDP is blocked, or real peer-to-peer is wanted

Best first, with the cost of each step.

1. **`wss://` on 443 — this code.** Nothing to build. Works wherever 443 is
   allowed and the name is not filtered.
2. **Tailscale DERP over 443/TLS.** Solves UDP blocking at the network layer
   with no change here, at the cost of a relay of last resort. Measured on a
   campus network where UDP was blocked: `tailscale netcheck` reported
   `UDP: false`, and `tailscale ping` returned "via DERP" at 330–443 ms with
   "direct connection not established". Expect relay latency, not direct
   latency. Not part of this code base.
3. **`wstunnel` / `udp2raw` (fake-TCP).** Purpose-built to carry UDP over
   TCP/TLS: they keep stream framing, reconnect, and (udp2raw) add replay
   protection. Constraints: udp2raw needs Linux with root and sends
   Windows/macOS users to a separate multiplatform build; phantun needs TUN
   plus nftables/iptables rules, so it is a Linux tool (its README documents no
   Windows target). Neither runs on iOS, so this covers machine-to-machine
   legs only — never the phone.
4. **`socat` — the last resort.** It has no framing: each datagram becomes its
   own connection, which a stateful tunnel (WireGuard, DNS over TCP) does not
   survive. It also nests a reliable stream inside a reliable stream — the inner
   connection retransmits into a buffer the outer connection retransmits again,
   so loss is amplified and latency spikes (the TCP-over-TCP meltdown). It needs
   an open port on the relay host, and 80 is the most scanned port on the
   Internet. And our protocol is not a UDP protocol at all: nothing on the app
   path can use socat.

## 5. Security baseline

- **TLS terminates at the proxy.** The Server has no TLS
  (`server/server.ts:48`) and forwards ciphertext only
  (`src/frames.ts:92-97`). Noise IK binds the handshake to the connection id and
  both device ids (`src/noise.ts:11`, `127-134`), so a relay operator sees
  metadata — device ids, timing, sizes — and no content.
- **Tokens** are bearer credentials for the relay. They are stored as SHA-256
  and compared in constant time (`server/store.ts:92-99`), the file is written
  `0600` (`server/store.ts:81`), and the table is capped at 100 000 devices
  (`server/store.ts:21`). The `hello` frame carries the token
  (`src/frames.ts:45-53`), so on the open Internet the transport must be TLS:
  otherwise an on-path observer can impersonate a device toward the relay. It
  still cannot read anything, and cannot impersonate the computer
  (`src/noise.ts:96-102`).
- **Limits** (`server/gateway.ts:40-50`, wired in `server/main.ts:7-17`,
  documented in `README.md:26-34`):

| Variable | Default | What it does |
|---|---|---|
| `DSBOT_LINK_MAX_SOCKETS` | 1024 | Sockets accepted in total (`server/gateway.ts:81`) |
| `DSBOT_LINK_MAX_LINKS` | 1024 | Phone-to-computer links in total (`server/gateway.ts:302`) |
| `DSBOT_LINK_MAX_SOCKETS_PER_ADDRESS` | 256 | Sockets from one address (`server/gateway.ts:85`) |
| `DSBOT_LINK_MAX_NEW_DEVICES_PER_HOUR` | 20 | New devices one address may register per hour (`server/gateway.ts:116-125`) |
| `DSBOT_LINK_DEVICE_TTL_DAYS` | none | Forget devices not seen for this long (`server/gateway.ts:127-133`) |
| `DSBOT_LINK_TRUST_PROXY` | off | Take the client address from `X-Forwarded-For` (`server/gateway.ts:101-108`) |

- **`DSBOT_LINK_TRUST_PROXY=1` is required behind a proxy, and only there.** The
  Server takes the *last* `X-Forwarded-For` entry
  (`server/gateway.ts:101-108`); with nginx's `$proxy_add_x_forwarded_for`
  that is the real client. Left off, every phone looks like the proxy, so
  `maxSocketsPerAddress` (256) and `maxNewDevicesPerHour` (20) apply to the
  whole world at once — one carrier-NAT site exhausts them. Turned on without a
  proxy, a client chooses its own address.
- **Origin**: a request whose `Origin` host differs from `Host` is refused
  (`server/gateway.ts:313-318`); native clients send none. Do not relax it.
- **Frame caps**: 1 MiB per frame (`server/gateway.ts:64`), 64 KiB control
  frames and 4 MiB per reassembled message (`src/frames.ts:4-7`).
- **`/healthz`** has no authentication (`server/server.ts:27-33`) and announces
  that the host is a relay. Expose it on purpose.

## 6. Reverse proxy, copy-paste

nginx — the `map` belongs in `http`:

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
  listen 443 ssl;
  http2 on;                          # nginx < 1.25.1: listen 443 ssl http2;
  server_name link.example.com;

  ssl_certificate     /etc/letsencrypt/live/link.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/link.example.com/privkey.pem;
  ssl_protocols       TLSv1.2 TLSv1.3;

  location = /v1/link {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host       $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffering    off;
    proxy_read_timeout 90s;          # must exceed the 25 s heartbeat
    proxy_send_timeout 90s;
  }

  location = /healthz {
    proxy_pass http://127.0.0.1:8787;
    access_log off;
  }
}
```

Caddy — upgrades and `X-Forwarded-For` are automatic:

```
link.example.com {
  reverse_proxy 127.0.0.1:8787
}
```

Run the Server on the loopback when the proxy is on the same host:

```sh
HOST=127.0.0.1 PORT=8787 \
DSBOT_LINK_DATA=/var/lib/dsbot-link/devices.json \
DSBOT_LINK_TRUST_PROXY=1 \
node server/main.ts
```

## What this does not cover

- Client-side HTTP proxies that are not transparent: the clients open a raw
  WebSocket (`src/relay-transport.ts:77`, `src/host.ts:205`), so whether the
  platform routes it through a system proxy is **unverified**.
- TLS trust rules on iOS and Android; the statements above come from platform
  behaviour, not from a test here.
- More than one relay address per pairing: the address travels in the pairing
  code (`src/pairing.ts:55-65`), so changing it means pairing the phone again.
