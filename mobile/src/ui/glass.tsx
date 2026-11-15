import { useState, type ReactNode } from 'react'
import { Pressable, StyleSheet, View, type PressableProps, type StyleProp, type ViewProps, type ViewStyle } from 'react-native'
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg'
import { GlassContainer, GlassView, isGlassEffectAPIAvailable, isLiquidGlassAvailable } from 'expo-glass-effect'
import { glass as metrics, radius as radii, shadow, useTheme } from './tokens.ts'

// Liquid Glass on iOS 26 renders through the system material; every other OS
// version draws the same surface from a translucent fill, a diagonal specular
// sweep, a hairline rim and the token shadow. Layout lives on the container in
// both paths, so nothing shifts when the material changes.

const native = ((): boolean => {
  try { return isGlassEffectAPIAvailable() && isLiquidGlassAvailable() } catch { return false }
})()

type Intensity = 'thin' | 'regular' | 'strong' | 'none'
const FILL = { thin: [0.06, 0.44], regular: [0.10, 0.62], strong: [0.16, 0.76], none: [0, 0] } as const
const SHEEN = { thin: 0.14, regular: 0.2, strong: 0.26 } as const
const TINT = { thin: 0.55, regular: 0.62, strong: 0.75 } as const
// Buttons take the clear material so the glyph stays the focus; larger surfaces
// carry text and take regular. An accent control needs regular to read as filled.
const NATIVE_STYLE = { thin: 'clear', regular: 'regular', strong: 'regular', none: 'none' } as const

const PAD = ['padding', 'paddingHorizontal', 'paddingVertical', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'] as const
// The glass paints its own fill, rim and shadow, so a converted card keeps only
// its layout: its padding moves inside the surface, its solid look is dropped.
const DROP = ['backgroundColor', 'borderWidth', 'borderColor', 'borderTopWidth', 'borderTopColor', 'borderBottomWidth', 'borderBottomColor', 'borderLeftWidth', 'borderLeftColor', 'borderRightWidth', 'borderRightColor', 'shadowColor', 'shadowOffset', 'shadowOpacity', 'shadowRadius', 'elevation'] as const

const rgba = (hex: string, alpha: number): string => {
  const raw = hex.replace('#', '')
  const full = raw.length === 3 ? raw.split('').map(part => part + part).join('') : raw
  const channels = [0, 2, 4].map(at => parseInt(full.slice(at, at + 2), 16))
  return `rgba(${channels.join(',')},${alpha})`
}

const split = (style?: StyleProp<ViewStyle>): { box: ViewStyle; pad: ViewStyle } => {
  const flat = StyleSheet.flatten(style) ?? {}
  const box: Record<string, unknown> = { ...flat }
  const pad: Record<string, unknown> = {}
  for (const key of [...PAD, ...DROP]) delete box[key]
  for (const key of PAD) if (flat[key as keyof ViewStyle] !== undefined) pad[key] = flat[key as keyof ViewStyle]
  return { box: box as ViewStyle, pad: pad as ViewStyle }
}

let serial = 0

export function Glass({ radius = radii.pill, intensity = 'regular', tint, interactive = false, accessibilityLabel, accessibilityRole, style, contentStyle, children }: {
  radius?: number
  intensity?: Intensity
  tint?: string
  interactive?: boolean
  accessibilityLabel?: string
  accessibilityRole?: ViewProps['accessibilityRole']
  style?: StyleProp<ViewStyle>
  contentStyle?: StyleProp<ViewStyle>
  children?: ReactNode
}) {
  const { dark } = useTheme()
  // One gradient id per mounted surface; two live glasses never share a definition.
  const [sheen] = useState(() => `glass${serial += 1}`)
  const { box, pad } = split(style)
  const body = <View style={[styles.content, pad, contentStyle]}>{children}</View>
  if (intensity === 'none') return <View accessibilityLabel={accessibilityLabel} accessibilityRole={accessibilityRole} style={[styles.plate, { borderRadius: radius }, box]}>{body}</View>
  if (native) {
    return (
      <GlassView
        glassEffectStyle={NATIVE_STYLE[intensity]}
        tintColor={tint}
        colorScheme={dark ? 'dark' : 'light'}
        isInteractive={interactive}
        accessibilityLabel={accessibilityLabel}
        accessibilityRole={accessibilityRole}
        style={[styles.plate, { borderRadius: radius }, box]}>
        {body}
      </GlassView>
    )
  }
  const fill = FILL[intensity]
  return (
    <View accessibilityLabel={accessibilityLabel} accessibilityRole={accessibilityRole} style={[styles.plate, { borderRadius: radius }, shadow(2), box]}>
      <View style={[styles.surface, {
        borderRadius: radius,
        borderColor: dark ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.55)',
        backgroundColor: `rgba(255,255,255,${dark ? fill[0] : fill[1]})`,
      }]}>
        {tint === undefined ? null : <View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: rgba(tint, TINT[intensity as keyof typeof TINT]) }]} />}
        <Svg pointerEvents="none" width="100%" height="100%" style={StyleSheet.absoluteFill}>
          <Defs>
            <LinearGradient id={sheen} x1="0" y1="0" x2="1" y2="1">
              <Stop offset="0" stopColor="#ffffff" stopOpacity={dark ? SHEEN[intensity as keyof typeof SHEEN] : Math.min(1, SHEEN[intensity as keyof typeof SHEEN] + 0.16)} />
              <Stop offset="0.55" stopColor="#ffffff" stopOpacity={0.05} />
              <Stop offset="1" stopColor="#ffffff" stopOpacity={0.01} />
            </LinearGradient>
          </Defs>
          <Rect x="0" y="0" width="100%" height="100%" fill={`url(#${sheen})`} />
        </Svg>
        {body}
      </View>
    </View>
  )
}

// Neighbouring glass merges where the system supports it; elsewhere this is the
// same plain row, so the two paths keep one layout.
export function GlassCluster({ spacing = 6, style, pointerEvents, children }: {
  spacing?: number
  style?: StyleProp<ViewStyle>
  pointerEvents?: 'box-none' | 'none' | 'auto' | 'box-only'
  children?: ReactNode
}) {
  if (!native) return <View style={style} pointerEvents={pointerEvents}>{children}</View>
  return <GlassContainer spacing={spacing} style={style} pointerEvents={pointerEvents}>{children}</GlassContainer>
}

// 44pt is the HIG minimum hit target; the icon slot keeps the glyph optically
// centred inside the circle.
export function GlassControl({ size = metrics.control, iconSize = metrics.icon, label, onPress, accent = false, dot = false, disabled = false, children }: {
  size?: number
  iconSize?: number
  label: string
  onPress: () => void
  accent?: boolean
  dot?: boolean
  disabled?: boolean
  children?: ReactNode
}) {
  const { p } = useTheme()
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled }} disabled={disabled} onPress={onPress} hitSlop={4}
      style={({ pressed }) => [styles.control, { width: size, height: size }, (pressed || disabled) && { opacity: disabled ? 0.35 : 0.7 }]}>
      <Glass radius={size / 2} intensity={accent ? 'strong' : 'thin'} tint={accent ? p.accent : undefined} interactive style={styles.fill}>
        <View style={{ width: iconSize, height: iconSize, alignItems: 'center', justifyContent: 'center' }}>{children}</View>
        {dot ? <View style={{ position: 'absolute', top: size * 0.17, right: size * 0.17, width: 8, height: 8, borderRadius: 4, backgroundColor: p.accent }} /> : null}
      </Glass>
    </Pressable>
  )
}

export function GlassPill({ height = metrics.pill, radius = radii.pill, tint, style, children }: {
  height?: number
  radius?: number
  tint?: string
  style?: StyleProp<ViewStyle>
  children?: ReactNode
}) {
  return (
    <Glass radius={radius} tint={tint} style={[{ height }, style]} contentStyle={styles.pillRow}>
      {children}
    </Glass>
  )
}

// A pressable whose whole box is the glass: the caller's minHeight keeps the
// hit target at 44, while the surface fills that box edge to edge.
export function GlassButton({ radius = radii.pill, intensity = 'regular', tint, accent = false, style, contentStyle, children, ...press }: {
  radius?: number
  intensity?: Intensity
  tint?: string
  accent?: boolean
  style?: StyleProp<ViewStyle>
  contentStyle?: StyleProp<ViewStyle>
  children?: ReactNode
} & Omit<PressableProps, 'style' | 'children'>) {
  const { p } = useTheme()
  const { box, pad } = split(style)
  return (
    <Pressable {...press} style={({ pressed }) => [box, press.disabled === true ? styles.off : pressed && styles.pressed]}>
      <Glass radius={radius} intensity={accent ? 'strong' : intensity} tint={accent ? p.accent : tint}
        style={styles.fill} contentStyle={[styles.buttonIn, pad, contentStyle]}>{children}</Glass>
    </Pressable>
  )
}

const styles = StyleSheet.create({
  plate: {},
  // flexGrow rather than flex:1, so a content-sized glass still measures itself.
  surface: { flexGrow: 1, overflow: 'hidden', borderWidth: StyleSheet.hairlineWidth },
  content: { flexGrow: 1 },
  control: { alignItems: 'stretch' },
  // Flow, not absolute: the glass measures itself from its content, so a button
  // without minHeight keeps its height instead of collapsing to zero.
  fill: { flexGrow: 1, alignSelf: 'stretch' },
  buttonIn: { alignItems: 'center', justifyContent: 'center' },
  pillRow: { flexDirection: 'row', alignItems: 'center', gap: metrics.gap, paddingHorizontal: 12 },
  pressed: { opacity: 0.7 },
  off: { opacity: 0.35 },
})
