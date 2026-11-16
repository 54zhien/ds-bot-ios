import { BlurView } from 'expo-blur'
import type { ReactNode } from 'react'
import { StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native'
import { rimSkin } from './material.tsx'
import { useTheme } from './tokens.ts'

// A system material surface (UIVisualEffectView). Liquid Glass is another
// pipeline and does not survive being transformed, so anything that lives in
// the sliding drawer stays on this one.
export function BlurSurface({ radius = 999, style, children }: {
  radius?: number
  style?: StyleProp<ViewStyle>
  children?: ReactNode
}) {
  const { dark } = useTheme()
  return (
    <View style={[{ borderRadius: radius, overflow: 'hidden' }, rimSkin(dark), style]}>
      <BlurView intensity={40} tint={dark ? 'dark' : 'light'} style={StyleSheet.absoluteFill} />
      {children}
    </View>
  )
}
