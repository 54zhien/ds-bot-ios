import type { ReactNode } from 'react'
import { Image, StyleSheet, Text, View } from 'react-native'
import { SvgXml } from 'react-native-svg'
import { characterMarkup, lookOf, MAIN_LOOK, MASK_ID, shapeOf } from '../../../ds-bot/src/client/characters.js'
import { INKS } from '../../../ds-bot/src/client/inks.js'
import type { Bot, Room } from '../connection.ts'
import { MainStarIcon } from './icons.tsx'
import { useTheme } from './tokens.ts'
import { materialSkin, rimSkin } from './material.tsx'

// The Bot's own mascot, drawn by the same generator as the desktop mark
// (ds-bot/src/client/characters.js). CSS ink variables resolve to the mode's color.

let serial = 0

// A character color as paint, for swatches and a member's name in a group.
export const COLOR_PAINT: Record<string, string> = {
  black: '#3c4048', brown: '#8d6e57', red: '#e5484d', orange: '#f76b15', yellow: '#d4a017',
  green: '#30a46c', cyan: '#12a5b4', blue: '#4f7df3', violet: '#7d5aff', magenta: '#d3458b', gray: '#8b8f98',
  aurora: '#5cc8a0',
}

export function botSvg(bot: unknown, dark: boolean): string {
  const look = lookOf(bot)
  const box = shapeOf(look.shape).size
  const id = `pm${serial += 1}`
  const inner = characterMarkup(look.shape, look.color).replaceAll(MASK_ID, id)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${box} ${box}">${inner}</svg>`
  const inks = INKS as Record<string, string[]>
  return svg.replace(/var\(--bt-ink-(\w+)\)/g, (_match, name: string) => (inks[name] ?? inks.gray)[dark ? 1 : 0])
}

const lookSvg = (look: { shape: string; color: string; image?: string }, dark: boolean): string => {
  const box = shapeOf(look.shape).size
  const id = `pm${serial += 1}`
  const inner = characterMarkup(look.shape, look.color).replaceAll(MASK_ID, id)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${box} ${box}">${inner}</svg>`
  const inks = INKS as Record<string, string[]>
  return svg.replace(/var\(--bt-ink-(\w+)\)/g, (_match, name: string) => (inks[name] ?? inks.gray)[dark ? 1 : 0])
}

export function Mark({ look, dark, size = 24 }: { look: { shape: string; color: string; image?: string }; dark: boolean; size?: number }) {
  if (typeof look.image === 'string' && look.image.startsWith('data:')) {
    return <Image source={{ uri: look.image }} style={{ width: size, height: size, borderRadius: size / 2 }} />
  }
  return (
    <View style={{ width: size, height: size }}>
      <SvgXml xml={lookSvg(look, dark)} width={size} height={size} />
    </View>
  )
}

export function BotMark({ bot, dark, size = 36 }: { bot: unknown; dark: boolean; size?: number }) {
  return <Mark look={lookOf(bot)} dark={dark} size={size} />
}

// The "You" avatar of the desktop sidebar's footer (YouAvatar): the whale mark.
export function YouMark({ dark, size = 24 }: { dark: boolean; size?: number }) {
  return <Mark look={MAIN_LOOK} dark={dark} size={size} />
}

// Status badges per ui-standard 8.2, scaled to the row's avatar: a waiting accent
// "?" and a working green dot, both dot-sized, both in a 2pt transparent gap so
// whatever sits behind the row shows through instead of a guessed ring colour.
export function Avatar({ bot, dark, size = 44, ring, working = false, waiting = false, main = false, bare = true }: {
  bot: Bot; dark: boolean; size?: number; ring: string; working?: boolean; waiting?: boolean; main?: boolean; bare?: boolean
}) {
  const star = Math.min(22, Math.max(14, Math.round(size * 0.36)))
  const dot = Math.round(size * 0.27)
  // Same value for both axes, so the badge sits exactly on the 45° diagonal.
  const inset = Math.round(size * 0.02)
  const gap = { padding: 2, right: inset, bottom: inset, backgroundColor: 'transparent' as const }
  return (
    <View style={{ width: size, height: size }}>
      <BotMark bot={bot} dark={dark} size={size} />
      {waiting
        ? <View style={[styles.badge, gap]}>
            <View style={{ width: dot, height: dot, borderRadius: dot / 2, backgroundColor: '#4d6bfe', alignItems: 'center', justifyContent: 'center' }}>
              <Text style={[styles.q, { color: '#fff', fontSize: dot * 0.66, lineHeight: dot }]}>?</Text>
            </View>
          </View>
        : working
          ? <View style={[styles.badge, gap]}>
              <View style={{ width: dot, height: dot, borderRadius: dot / 2, backgroundColor: '#00c972' }} />
            </View>
          : null}
      {main ? <View style={[styles.star, { width: star, height: star, right: -size * 0.07, bottom: -size * 0.07 }]}><MainStarIcon size={star} ring={ring} /></View> : null}
    </View>
  )
}

// A group avatar seats its members' characters like the desktop's RoomAvatar
// (mark.js:129-175). The gaps are cut with an SVG mask instead of a ring in a
// guessed background color, so they show whatever is behind the avatar — the
// glass pill in the chat header included.
function clusterSeats(count: number, frame: number): [number, number, number][] {
  if (count === 1) return [[0, 0, frame]]
  if (count === 2) return [[0, 0, frame * 2 / 3], [frame / 3, frame / 3, frame * 2 / 3]]
  if (count === 3) {
    const size = frame * 5 / 9
    const rest = frame - size
    return [[rest / 2, 0, size], [0, rest, size], [rest, rest, size]]
  }
  const half = frame / 2
  return [[0, 0, half], [half, 0, half], [0, half, half], [half, half, half]]
}

const inkOf = (markup: string, dark: boolean): string => {
  const inks = INKS as Record<string, string[]>
  return markup.replace(/var\(--bt-ink-(\w+)\)/g, (_match, name: string) => (inks[name] ?? inks.gray)[dark ? 1 : 0])
}

export function RoomAvatar({ room, bots, dark, size = 44, ring }: { room: Room; bots: Bot[]; dark: boolean; size?: number; ring: string }) {
  const { p } = useTheme()
  const byId = new Map(bots.map(bot => [bot.id, bot]))
  const members = (room.members ?? []).map(id => byId.get(id)).filter((bot): bot is Bot => bot !== undefined)
  // A group with one Bot left shows the user beside it (mark.js:145-149).
  const people: (Bot | null)[] = members.length === 1 ? [members[0], null] : members
  if (people.length === 0) {
    return <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: ring }} />
  }
  // Only inline sizes fall back to the overlapping stack (mark.js:151-156); a
  // 28pt seat still has room for a cluster.
  if (size <= 20 && people.length > 1) {
    const overlap = size * 0.3
    return (
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        {people.slice(0, 3).map((bot, index) => (
          <View key={bot?.id ?? `you-${index}`} style={{ marginLeft: index === 0 ? 0 : -overlap, zIndex: people.length - index }}>
            {bot === null
              ? <View style={{ width: size * 0.92, height: size * 0.92, borderRadius: size / 2, backgroundColor: p.lineWeak }} />
              : <BotMark bot={bot} dark={dark} size={size} />}
          </View>
        ))}
        {people.length > 3 ? <Text style={{ fontSize: 11, lineHeight: 16, fontWeight: '500', color: p.ink3, marginLeft: 3 }}>{`+${people.length - 3}`}</Text> : null}
      </View>
    )
  }
  const seats = clusterSeats(Math.min(people.length, 4), size)
  const overflow = people.length > 4 ? people.length - 3 : 0
  const gap = size / 14
  // Each later seat cuts a gap of frame/14 into the seats it overlaps (mark.js:159-166).
  const rings = seats.map(([x, y, s]) => ({ cx: x + s / 2, cy: y + s / 2, r: s * 0.48 + gap }))
  const base = `cl${serial += 1}`
  const defs: string[] = []
  const marks: string[] = []
  const overlays: ReactNode[] = []
  seats.forEach(([x, y, s], index) => {
    const holes = rings.slice(index + 1)
      .filter(ring => Math.hypot(ring.cx - x - s / 2, ring.cy - y - s / 2) < ring.r + s * 0.46)
    if (holes.length > 0) {
      const id = `${base}-${index}`
      defs.push(`<mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="${size}" height="${size}"><rect x="0" y="0" width="${size}" height="${size}" fill="#fff"/>${holes.map(hole => `<circle cx="${hole.cx}" cy="${hole.cy}" r="${hole.r}" fill="#000"/>`).join('')}</mask>`)
    }
    if (overflow > 0 && index === 3) {
      overlays.push(
        <View key="more" style={[styles.seat, {
          left: x + s * 0.04, top: y + s * 0.04, width: s * 0.92, height: s * 0.92, borderRadius: s / 2,
          alignItems: 'center', justifyContent: 'center',
        }, materialSkin(dark, s / 2)]}>
          <Text style={{ fontSize: Math.max(8, Math.round(s * 0.36)), lineHeight: s * 0.92, fontWeight: '500', color: p.ink2 }}>{`+${overflow}`}</Text>
        </View>,
      )
      return
    }
    const bot = people[index]
    if (bot === null) {
      // The user's own seat: a quiet disc, not a character (mark.js:149).
      overlays.push(<View key="you" style={[styles.seat, { left: x + s * 0.04, top: y + s * 0.04, width: s * 0.92, height: s * 0.92, borderRadius: s / 2, backgroundColor: 'transparent' }, rimSkin(dark)]} />)
      return
    }
    const look = lookOf(bot)
    if (typeof look.image === 'string' && look.image.startsWith('data:')) {
      overlays.push(<Image key={bot.id} source={{ uri: look.image }} style={[styles.seat, { left: x, top: y, width: s, height: s, borderRadius: s / 2 }]} />)
      return
    }
    const box = shapeOf(look.shape).size
    const markup = inkOf(characterMarkup(look.shape, look.color).replaceAll(MASK_ID, `pm${serial += 1}`), dark)
    const mask = holes.length === 0 ? '' : ` mask="url(#${base}-${index})"`
    // The transform sits on an inner group so the mask keeps the frame's own
    // coordinates, whatever the seat is scaled to.
    marks.push(`<g${mask}><g transform="translate(${x} ${y}) scale(${s / box})">${markup}</g></g>`)
  })
  return (
    <View style={{ width: size, height: size }}>
      {marks.length > 0
        ? <SvgXml xml={`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}"><defs>${defs.join('')}</defs>${marks.join('')}</svg>`} width={size} height={size} />
        : null}
      {overlays}
    </View>
  )
}

const styles = StyleSheet.create({
  badge: { position: 'absolute', alignItems: 'center', justifyContent: 'center' },
  star: { position: 'absolute' },
  q: { fontWeight: '600', textAlign: 'center' },
  seat: { position: 'absolute', overflow: 'hidden' },
})
