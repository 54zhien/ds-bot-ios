import { createContext, useContext } from 'react'
import { Dimensions, Platform } from 'react-native'
import { allThemes } from '../../../ds-bot/src/client/themes.js'
import { ACCENT_INKS, INKS, luminance } from '../../../ds-bot/src/client/inks.js'

// The phone palette derives from the same eight theme colors as the desktop team
// UI (ds-bot/src/client/themes.js), through allThemes() so custom themes follow too.

export interface ThemeMode {
  bg: string; sidebar: string; bubble: string; card: string
  text: string; user: string; userText: string; accent: string
}

const DARK_INK = '#141414'
const accentInk = (accent: string) =>
  (luminance(accent) + 0.05) ** 2 > 1.05 * (luminance(DARK_INK) + 0.05) ? DARK_INK : '#ffffff'
export const rgba = (hex: string, alpha: number) =>
  `rgba(${[1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16)).join(',')},${alpha})`

// Stands in for CSS color-mix: the desktop tints a badge with the surface behind
// it, and the phone has no color-mix of its own.
export const mix = (a: string, b: string, weightOfA: number): string => {
  if (!/^#[0-9a-f]{6}$/i.test(a) || !/^#[0-9a-f]{6}$/i.test(b)) return a
  const channel = (hex: string, at: number) => parseInt(hex.slice(at, at + 2), 16)
  return `#${[1, 3, 5]
    .map(at => Math.round(channel(a, at) * weightOfA + channel(b, at) * (1 - weightOfA)).toString(16).padStart(2, '0'))
    .join('')}`
}

const inks = INKS as Record<string, string[]>

// A preset accent is saved as its light value; in dark mode it takes the preset's dark
// value, like Bot names. A custom accent is the same in both modes.
const darkAccent = (accent: string): string => {
  const ink = ACCENT_INKS.find(id => inks[id][0] === accent)
  return ink === undefined ? accent : inks[ink][1]
}

export interface Palette {
  ink: string; ink2: string; ink3: string
  bubble: string; sidebar: string; main: string; card: string
  line: string; line2: string; lineWeak: string
  hover: string; active: string
  accent: string; accentInk: string
  user: string; userInk: string
  tagBg: string; tagInk: string
  knob: string
  danger: string; green: string; star: string
}

export function palette(dark: boolean, themeId?: string, accent?: string): Palette {
  const themes = allThemes() as Record<string, { label: string; light: ThemeMode; dark: ThemeMode }>
  const theme = themes[themeId ?? ''] ?? themes.deepseek
  const mode = dark ? theme.dark : theme.light
  const use = accent === undefined ? mode.accent : dark ? darkAccent(accent) : accent
  return {
    ink: mode.text, ink2: rgba(mode.text, 0.6), ink3: rgba(mode.text, 0.36),
    bubble: mode.bubble, sidebar: mode.sidebar, main: mode.bg, card: mode.card,
    line: rgba(mode.text, 0.08), line2: rgba(mode.text, 0.15), lineWeak: rgba(mode.text, 0.1),
    hover: dark ? 'rgba(160,160,160,.12)' : 'rgba(119,119,119,.09)',
    active: dark ? 'rgba(160,160,160,.2)' : 'rgba(119,119,119,.17)',
    accent: use, accentInk: accentInk(use),
    user: mode.user, userInk: mode.userText,
    tagBg: rgba(mode.text, dark ? 0.09 : 0.06), tagInk: rgba(mode.text, 0.58),
    knob: '#ffffff',
    danger: '#e02135', green: '#00c972', star: '#ff9800',
  }
}

export function themeLabel(themeId?: string): string {
  const themes = allThemes() as Record<string, { label: string }>
  return themes[themeId ?? '']?.label ?? themes.deepseek.label
}

// A Bot's color, resolved the way names and marks do on the desktop: a named ink has
// a light and a dark value, a #rrggbb color is used as is.
export function inkColor(color: string | undefined, dark: boolean): string {
  if (color !== undefined && inks[color] !== undefined) return inks[color][dark ? 1 : 0]
  if (color !== undefined && /^#[0-9a-f]{6}$/i.test(color)) return color
  return inks.gray[dark ? 1 : 0]
}

// The 9.1 springs as Reanimated configs: stiffness = w^2, damping = 2*zeta*w, mass 1.
export const springOf = (w: number, z: number) => ({ mass: 1, stiffness: w * w, damping: 2 * z * w })
export const SPRING_SHAPE = springOf(20, 0.78)
export const SPRING_TAP = springOf(30, 0.8)
export const SPRING_LIST = springOf(22, 0.8)
export const SPRING_STRETCH = springOf(18, 0.56)
export const SPRING_POP = springOf(22, 0.49)

// Phone type scale: settled sizes for touch, weights only 400/500/600.
export const type = {
  rowName: { fontSize: 16, lineHeight: 22, fontWeight: '400' as const },
  rowPreview: { fontSize: 14, lineHeight: 20, fontWeight: '400' as const },
  bubble: { fontSize: 16, lineHeight: 24, fontWeight: '400' as const },
  headerTitle: { fontSize: 17, lineHeight: 24, fontWeight: '600' as const },
  largeTitle: { fontSize: 28, lineHeight: 34, fontWeight: '600' as const },
  settingsRow: { fontSize: 16, lineHeight: 22, fontWeight: '400' as const },
  small: { fontSize: 13, lineHeight: 18, fontWeight: '400' as const },
  caption: { fontSize: 12, lineHeight: 16, fontWeight: '400' as const },
}

export const radius = { tag: 4, item: 6, input: 8, row: 10, card: 12, option: 12, dialog: 16, bubble: 18, composer: 22, composerLong: 18, pill: 999 }

// Shadow levels 0-4 from the standard, mapped to iOS shadow + subtle Android elevation.
export const shadow = (level: 0 | 1 | 2 | 3 | 4, color = '#000') => {
  const android = Platform.OS === 'android'
  return [
    {},
    { shadowColor: android ? 'rgba(0,0,0,0.28)' : color, shadowOffset: { width: 0, height: 2 }, shadowRadius: 8, shadowOpacity: 0.06, elevation: 1 },
    { shadowColor: android ? 'rgba(0,0,0,0.35)' : color, shadowOffset: { width: 0, height: 10 }, shadowRadius: 20, shadowOpacity: 0.1, elevation: 4 },
    { shadowColor: android ? 'rgba(0,0,0,0.4)' : color, shadowOffset: { width: 0, height: 8 }, shadowRadius: 28, shadowOpacity: 0.14, elevation: 8 },
    { shadowColor: android ? 'rgba(0,0,0,0.5)' : color, shadowOffset: { width: 0, height: 24 }, shadowRadius: 80, shadowOpacity: 0.24, elevation: 14 },
  ][level]
}

// Liquid Glass metrics: every glass surface takes its sizes from here.
export const glass = { control: 44, controlSmall: 40, icon: 22, iconLarge: 24, iconXL: 26, pill: 44, gap: 8, margin: 16 }

// The floating chat header is the status bar plus the 44pt bar plus 8 below it.
// Screens that have to clear it (list padding, goal bar, fade layers) ask here.
export const headerHeight = (insetTop: number) => insetTop + glass.control + 8

// Approximate display corner radius: iOS devices with a home indicator round the
// display at about 55pt, SE-class screens are square. Swap in a real value once
// the platform exposes one.
export const screenRadius = (bottomInset: number, os: string): number => {
  if (os !== 'ios') return 0
  // Read per call, not once: rotation and stage manager change the window.
  const { width, height } = Dimensions.get('window')
  if (Math.min(width, height) >= 600) return 18
  return bottomInset >= 20 ? 55 : 0
}

// A resting composer is inset and lifted by R - h/2, so its end circles share the
// display corner's centre. Clamped: never sneak toward the middle, never hug the edge.
export const concentricInset = (screenR: number, height: number): number =>
  screenR === 0 ? 16 : Math.min(32, Math.max(12, screenR - height / 2))

// The resting composer's height, so anything that has to line up with it can ask
// for the same inset instead of keeping its own copy of the number.
export const COMPOSER_RESTING = Math.max(50, 22 + 20) + 12

// Left inset of the composer: the standard margin while editing, the concentric
// one at rest, 12 on Android — unless the text area would not fit at all.
export const composerInset = ({ screenR, screenWidth, expanded, android }: {
  screenR: number; screenWidth: number; expanded: boolean; android: boolean
}): number => {
  if (android) return 12
  if (expanded) return glass.margin
  const tight = concentricInset(screenR, COMPOSER_RESTING)
  return screenWidth - 2 * tight - 88 >= 120 ? tight : glass.margin
}

export const MONO = 'monospace'

export interface Theme { dark: boolean; p: Palette }
export const ThemeContext = createContext<Theme>({ dark: false, p: palette(false) })
export const useTheme = () => useContext(ThemeContext)
