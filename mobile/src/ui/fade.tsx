import RawMaskedView from '@react-native-masked-view/masked-view'
import { BlurView } from 'expo-blur'
import { useState, type ComponentType, type ReactNode } from 'react'
import { Platform, StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native'
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg'
import { useTheme } from './tokens.ts'

// One blur view behind a CAGradientLayer-style alpha mask, the way rex does it:
// the material is real, and the mask decides how much of it shows, so content
// blurs and fades out instead of being covered by a solid strip. Off iOS the blur
// is skipped and the same curve is drawn as a plain page-colour gradient.
// The package still types its view for React 17 JSX; the runtime is fine.
const MaskedView = RawMaskedView as unknown as ComponentType<{ maskElement: ReactNode; style?: StyleProp<ViewStyle>; children?: ReactNode }>
const STOPS = [0, 0.25, 0.6, 1]
const ALPHA = [0, 0.28, 0.78, 1]
const INTENSITY = 48

export function GlassFade({ edge, height, radius = 0, color, plain = false }: {
  edge: 'top' | 'bottom'
  height: number
  radius?: number
  color?: string
  /** Draw the curve without MaskedView. Required inside any transform-animated parent: a native mask in a moving layer crashes. */
  plain?: boolean
}) {
  const { dark, p } = useTheme()
  const [id] = useState(() => `fade${(fadeSerial += 1)}`)
  const paper = color ?? p.main
  // The mask is transparent where the content starts and opaque at the screen edge.
  const alpha = edge === 'top' ? [...ALPHA].reverse() : ALPHA
  const wash = (
    <Svg width="100%" height="100%">
      <Defs>
        <LinearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          {STOPS.map((offset, i) => <Stop key={offset} offset={offset} stopColor={paper} stopOpacity={alpha[i]} />)}
        </LinearGradient>
      </Defs>
      <Rect width="100%" height="100%" fill={`url(#${id})`} />
    </Svg>
  )
  if (plain) {
    return (
      <View pointerEvents="none" style={[styles.wrap, { height, borderRadius: radius }, edge === 'top' ? { top: 0 } : { bottom: 0 }]}>
        {wash}
      </View>
    )
  }
  const mask = (
    <Svg width="100%" height="100%">
      <Defs>
        <LinearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          {STOPS.map((offset, i) => <Stop key={offset} offset={offset} stopColor="#000000" stopOpacity={alpha[i]} />)}
        </LinearGradient>
      </Defs>
      <Rect width="100%" height="100%" fill={`url(#${id})`} />
    </Svg>
  )
  return (
    <View pointerEvents="none" style={[styles.wrap, { height, borderRadius: radius }, edge === 'top' ? { top: 0 } : { bottom: 0 }]}>
      {Platform.OS === 'ios'
        ? <MaskedView style={StyleSheet.absoluteFill} maskElement={mask}>
            <BlurView style={StyleSheet.absoluteFill} intensity={INTENSITY} tint={dark ? 'dark' : 'light'} pointerEvents="none" />
          </MaskedView>
        : mask}
    </View>
  )
}

let fadeSerial = 0

// Above page content (the goal bar sits at 1), below the floating bar (10).
const styles = StyleSheet.create({ wrap: { position: 'absolute', left: 0, right: 0, zIndex: 9, overflow: 'hidden' } })
