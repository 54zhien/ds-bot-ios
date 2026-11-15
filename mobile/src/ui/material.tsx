import type { ReactNode } from 'react'
import { StyleSheet, View, type StyleProp, type ViewProps, type ViewStyle } from 'react-native'
import { useTheme } from './tokens.ts'

// Material, not glass: a flat translucent fill and a 1pt rim. It is for surfaces
// that sit inside other surfaces — cards in a sheet, a segmented row — where a
// blur would smear what is behind them and cost a layer for nothing.

const DROP = ['backgroundColor', 'borderWidth', 'borderColor', 'borderTopWidth', 'borderTopColor', 'borderBottomWidth', 'borderBottomColor', 'borderLeftWidth', 'borderLeftColor', 'borderRightWidth', 'borderRightColor', 'shadowColor', 'shadowOffset', 'shadowOpacity', 'shadowRadius', 'elevation'] as const

const strip = (style?: StyleProp<ViewStyle>): ViewStyle => {
  const flat = { ...(StyleSheet.flatten(style) ?? {}) } as Record<string, unknown>
  for (const key of DROP) delete flat[key]
  return flat as ViewStyle
}

// One rim for everything we draw ourselves: 1pt, never hairline (invisible in dark),
// 1.5 at 0.35 for a selected chip.
export const rimSkin = (dark: boolean, selected = false): ViewStyle => ({
  borderWidth: selected ? 1.5 : 1,
  borderColor: selected
    ? dark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.35)'
    : dark ? 'rgba(255,255,255,0.09)' : 'rgba(0,0,0,0.08)',
})

// The same ramp for a Pressable or TextInput that already owns its own layout.
export const materialSkin = (dark: boolean, radius: number, selected = false): ViewStyle => ({
  backgroundColor: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.045)',
  borderRadius: radius,
  ...rimSkin(dark, selected),
})

export function Material({ radius = 999, selected = false, plain = false, accessibilityLabel, accessibilityRole, style, children }: {
  radius?: number
  selected?: boolean
  plain?: boolean
  accessibilityLabel?: string
  accessibilityRole?: ViewProps['accessibilityRole']
  style?: StyleProp<ViewStyle>
  children?: ReactNode
}) {
  const { dark } = useTheme()
  if (plain) return <View accessibilityLabel={accessibilityLabel} accessibilityRole={accessibilityRole} style={[{ borderRadius: radius }, strip(style)]}>{children}</View>
  return (
    <View accessibilityLabel={accessibilityLabel} accessibilityRole={accessibilityRole} style={[styles.base, materialSkin(dark, radius, selected), strip(style)]}>
      {children}
    </View>
  )
}

// A single-line control: capsule, so its ends are circles of height / 2.
export function MaterialRow({ height = 48, selected = false, plain = false, style, children }: {
  height?: number
  selected?: boolean
  plain?: boolean
  style?: StyleProp<ViewStyle>
  children?: ReactNode
}) {
  return <Material radius={height / 2} selected={selected} plain={plain} style={[styles.row, { minHeight: height }, style]}>{children}</Material>
}

const styles = StyleSheet.create({ base: {}, row: { flexDirection: 'row', alignItems: 'center' } })
