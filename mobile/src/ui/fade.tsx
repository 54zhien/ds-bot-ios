import { useState } from 'react'
import { StyleSheet, View } from 'react-native'
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg'

// A hand-drawn header gets no system scroll edge effect, so the page colour is
// laid over the list edge: solid under the bar, clear where the content starts.
let serial = 0
export function Fade({ color, height, edge }: { color: string; height: number; edge: 'top' | 'bottom' }) {
  const [id] = useState(() => `fade${serial += 1}`)
  const alpha = edge === 'top' ? [1, 0.78, 0.28, 0] : [0, 0.28, 0.78, 1]
  return (
    <View pointerEvents="none" style={[styles.fade, { height }, edge === 'top' ? { top: 0 } : { bottom: 0 }]}>
      <Svg width="100%" height="100%">
        <Defs>
          <LinearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={color} stopOpacity={alpha[0]} />
            <Stop offset="0.25" stopColor={color} stopOpacity={alpha[1]} />
            <Stop offset="0.6" stopColor={color} stopOpacity={alpha[2]} />
            <Stop offset="1" stopColor={color} stopOpacity={alpha[3]} />
          </LinearGradient>
        </Defs>
        <Rect width="100%" height="100%" fill={`url(#${id})`} />
      </Svg>
    </View>
  )
}

const styles = StyleSheet.create({ fade: { position: 'absolute', left: 0, right: 0 } })
