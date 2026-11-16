import * as Haptics from 'expo-haptics'
import * as ImagePicker from 'expo-image-picker'
import { manipulateAsync, SaveFormat } from 'expo-image-manipulator'
import { BlurView } from 'expo-blur'
import { useEffect, useState } from 'react'
import { ActivityIndicator, Image, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, useWindowDimensions, View } from 'react-native'
import Animated, { interpolate, useAnimatedStyle, useSharedValue, withSpring } from 'react-native-reanimated'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { t } from '../../ui/i18n.ts'
import { ArrowUpIcon, CloseIcon, PlusIcon, StopIcon } from '../../ui/icons.tsx'
import { Glass, GlassControl } from '../../ui/glass.tsx'
import { rimSkin } from '../../ui/material.tsx'
import { COMPOSER_RESTING, composerInset, concentricInset, screenRadius, SPRING_SHAPE, type as typeScale, type Palette, useTheme } from '../../ui/tokens.ts'

// A photo ready to send: shown from `uri`, sent as base64 JPEG.
export interface Photo { uri: string; mediaType: string; data: string }

// Photos are made smaller on the phone before they go: the long side at most
// 2048 px as JPEG, which keeps one photo well under what the link carries in a
// message and is as much as the models look at.
const LONG_SIDE = 2048
async function prepare(asset: ImagePicker.ImagePickerAsset): Promise<Photo> {
  const long = Math.max(asset.width ?? 0, asset.height ?? 0)
  const resize = long > LONG_SIDE ? [{ resize: asset.width >= asset.height ? { width: LONG_SIDE } : { height: LONG_SIDE } }] : []
  const out = await manipulateAsync(asset.uri, resize, { compress: 0.82, format: SaveFormat.JPEG, base64: true })
  return { uri: out.uri, mediaType: 'image/jpeg', data: out.base64 ?? '' }
}

// zen's ComposerGeometry: a resting capsule that shares the display corner's centre
// (inset = R - h/2), and an editing card from 124 up to 46% of the screen with a
// 52pt control rail. The state is the same one zen resolves: editing while it holds
// the focus, a draft or an attachment. The surface is a system material, not a
// tinted glass. One TextInput changes shape only — never identity — so focusing it
// does not tear the keyboard down.
const LINE = 22
const RESTING = COMPOSER_RESTING
const EDITING = 124
const TEXT_TOP = 14
const BAR = 52
const EDITING_BOTTOM = 12
const CARD_CORNER = 26
const MEDIA = 80
// A neutral frost: no tinted layer of its own, so the page colour stays put.
const SURFACE_BLUR = 12

export function Composer({ name, running, canStop, canAttach, keyboardUp, onSend, onStop, onInset, p }: {
  name: string; running: boolean; canStop: boolean; canAttach: boolean; keyboardUp: boolean
  onSend: (text: string, photos: Photo[]) => Promise<void>; onStop: () => void
  onInset?: (inset: number) => void; p: Palette
}) {
  const [text, setText] = useState('')
  const [photos, setPhotos] = useState<Photo[]>([])
  const [preparing, setPreparing] = useState(false)
  const [pickError, setPickError] = useState<string | null>(null)
  const [focused, setFocused] = useState(false)
  const [textHeight, setTextHeight] = useState(LINE)
  const { dark } = useTheme()
  const insets = useSafeAreaInsets()
  const { width: screenWidth, height: windowHeight } = useWindowDimensions()
  const draft = text.trim()
  const ready = (draft !== '' || photos.length > 0) && !preparing
  // The message shows in the chat at once; the composer is free for the next one.
  const send = () => {
    if (!ready) return
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)
    const sending = photos
    setText(''); setPhotos([])
    void onSend(draft, sending)
  }
  const pick = async () => {
    setPickError(null)
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: true, selectionLimit: 0, quality: 1, orderedSelection: true })
    if (result.canceled || result.assets.length === 0) return
    setPreparing(true)
    try {
      const ready = await Promise.all(result.assets.map(prepare))
      setPhotos(prev => [...prev, ...ready.filter(photo => photo.data !== '')])
    } catch (failure) {
      setPickError(failure instanceof Error ? failure.message : String(failure))
    } finally { setPreparing(false) }
  }
  // zen's resolve(): editing while it holds the focus, a draft or a photo.
  const hasMedia = photos.length > 0 || preparing
  const media = hasMedia ? MEDIA : 0
  const expanded = focused || draft !== '' || hasMedia
  const available = windowHeight - insets.top
  const cap = Math.min(available - 12, Math.max(available * 0.46, TEXT_TOP + BAR + LINE))
  const room = Math.max(LINE, cap - TEXT_TOP - media - BAR)
  const cardHeight = expanded ? Math.min(cap, Math.max(EDITING, TEXT_TOP + media + Math.min(textHeight, room) + BAR)) : RESTING
  // The rail and the media row are reserved first; the field gets what is left and
  // scrolls inside it, so the controls can never be pushed out of the card.
  const textMax = Math.max(LINE, cardHeight - TEXT_TOP - media - BAR)
  const screenR = screenRadius(insets.bottom, Platform.OS)
  const android = Platform.OS === 'android'
  const inset = composerInset({ screenR, screenWidth, expanded, android })
  const stop = running && canStop && !ready
  // Reported after paint: the row above the dock lines up with this same value.
  useEffect(() => { onInset?.(inset) }, [inset, onInset])
  // One spring drives the shell and the rail, so nothing lands on a different frame.
  const progress = useSharedValue(expanded ? 1 : 0)
  useEffect(() => { progress.value = withSpring(expanded ? 1 : 0, SPRING_SHAPE) }, [expanded, progress])
  const restInset = composerInset({ screenR, screenWidth, expanded: false, android })
  const openInset = composerInset({ screenR, screenWidth, expanded: true, android })
  const restBottom = android ? Math.max(insets.bottom, 10) : concentricInset(screenR, RESTING)
  const openBottom = android ? restBottom : EDITING_BOTTOM
  // zen's .containerConcentric: the card's corner is concentric with the display's,
  // not a fixed number, so it reads as a sheet rather than a rounded box.
  const openCorner = Math.max(CARD_CORNER, screenR - openInset)
  const corner = expanded ? openCorner : RESTING / 2
  const shellStyle = useAnimatedStyle(() => ({
    height: interpolate(progress.value, [0, 1], [RESTING, cardHeight]),
    marginHorizontal: interpolate(progress.value, [0, 1], [restInset, openInset]),
    // The keyboard owns the distance while it is up; nothing is animated over it.
    marginBottom: keyboardUp && !android ? EDITING_BOTTOM : interpolate(progress.value, [0, 1], [restBottom, openBottom]),
    borderRadius: interpolate(progress.value, [0, 1], [RESTING / 2, openCorner]),
    // The corner is the shell's: the surface paints square and is clipped here.
    overflow: 'hidden' as const,
  }))
  const rimStyle = useAnimatedStyle(() => ({ borderRadius: interpolate(progress.value, [0, 1], [RESTING / 2, openCorner]) }))
  // The blur is clipped twice: the shell, and this wrapper, in case the native view
  // paints past a clipped parent.
  const surfaceStyle = useAnimatedStyle(() => ({
    borderRadius: interpolate(progress.value, [0, 1], [RESTING / 2, openCorner]),
    overflow: 'hidden' as const,
  }))
  const barStyle = useAnimatedStyle(() => ({
    height: interpolate(progress.value, [0, 1], [0, BAR]),
    opacity: progress.value,
  }))
  const sendButton = stop
    ? <GlassControl label={t('Stop')} onPress={onStop}><StopIcon size={26} /></GlassControl>
    : <GlassControl label={t('Send')} accent disabled={!ready} onPress={send}><ArrowUpIcon size={26} /></GlassControl>
  return (
    <View>
      {pickError !== null ? <Text style={[typeScale.small, { color: p.danger, textAlign: 'center', marginBottom: 4 }]}>{pickError}</Text> : null}
      {/* The shell owns height, margins and the corner; the surface fills it edge to edge. */}
      <Animated.View style={shellStyle}>
        {android
          ? <Glass radius={corner} intensity="thin" flat style={StyleSheet.absoluteFill} />
          : (
            <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, surfaceStyle]}>
              <BlurView intensity={SURFACE_BLUR} tint="default" style={StyleSheet.absoluteFill} />
            </Animated.View>
          )}
        {android ? null : <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, rimSkin(dark), rimStyle]} />}
        <View style={styles.card}>
          {photos.length > 0 || preparing ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.media} contentContainerStyle={styles.photos} keyboardShouldPersistTaps="handled">
              {photos.map(photo => (
                <View key={photo.uri}>
                  <Image source={{ uri: photo.uri }} style={[styles.photo, { backgroundColor: p.hover }]} />
                  <Pressable accessibilityRole="button" accessibilityLabel={t('Remove')} hitSlop={8} onPress={() => setPhotos(prev => prev.filter(entry => entry !== photo))}
                    style={[styles.unpick, { backgroundColor: p.ink }]}>
                    <CloseIcon size={10} color={p.main} />
                  </Pressable>
                </View>
              ))}
              {preparing ? <View style={[styles.photo, { backgroundColor: p.hover, alignItems: 'center', justifyContent: 'center' }]}><ActivityIndicator color={p.ink3} /></View> : null}
            </ScrollView>
          ) : null}
          {/* One TextInput for both states: it keeps focus and the keyboard while the card grows. */}
          <View style={[styles.row, expanded && styles.rowOpen]}>
            {!expanded && canAttach
              ? <Pressable accessibilityRole="button" accessibilityLabel={t('Add photos')} onPress={() => void pick()} hitSlop={2} style={styles.hit}>
                  <PlusIcon size={24} color={p.ink2} />
                </Pressable>
              : <View style={styles.hit} />}
            <View style={[styles.field, expanded && styles.fieldOpen, expanded && { maxHeight: TEXT_TOP + textMax }]}>
              <TextInput value={text} onChangeText={setText} placeholder={t('Message {name}', { name })} placeholderTextColor={p.ink3}
                multiline scrollEnabled={expanded} onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
                onContentSizeChange={event => setTextHeight(event.nativeEvent.contentSize.height)}
                style={[styles.input, expanded ? styles.inputOpen : styles.inputResting, expanded && { maxHeight: textMax }, { color: p.ink }]} accessibilityLabel={t('Message {name}', { name })} />
            </View>
            {expanded ? null : sendButton}
          </View>
          {/* Always mounted: it grows out of the card instead of popping in. */}
          <Animated.View style={[styles.bar, barStyle]}>
            {canAttach
              ? <Pressable accessibilityRole="button" accessibilityLabel={t('Add photos')} onPress={() => void pick()} hitSlop={2} style={styles.hit}>
                  <PlusIcon size={24} color={p.ink2} />
                </Pressable>
              : <View style={styles.hit} />}
            {sendButton}
          </Animated.View>
        </View>
      </Animated.View>
    </View>
  )
}

const styles = StyleSheet.create({
  card: { flex: 1, alignItems: 'stretch', overflow: 'hidden' },
  media: { flexGrow: 0, flexShrink: 0 },
  photos: { gap: 8, paddingHorizontal: 9, paddingTop: 9 },
  photo: { width: 64, height: 64, borderRadius: 12 },
  unpick: { position: 'absolute', top: -5, right: -5, width: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', flexGrow: 1, flexShrink: 1, minHeight: 0, paddingHorizontal: 9 },
  rowOpen: { alignItems: 'stretch', paddingHorizontal: 0 },
  hit: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  // Resting: the field centres the 22pt line box in the 62pt capsule.
  field: { flex: 1, minWidth: 0, justifyContent: 'center' },
  // Editing: the line box starts at the editor's 14pt top inset and grows downward.
  fieldOpen: { flexGrow: 1, flexShrink: 1, minHeight: 0, justifyContent: 'flex-start', paddingTop: TEXT_TOP, paddingHorizontal: 12 },
  // No vertical padding in either state: it would move the caret line box and drift
  // the placeholder, which is why one padding cannot serve both.
  input: { flexShrink: 1, minHeight: 0, fontSize: 16, lineHeight: LINE, paddingVertical: 0, paddingHorizontal: 0 },
  inputResting: { paddingHorizontal: 3 },
  inputOpen: {},
  bar: { height: BAR, flexShrink: 0, overflow: 'hidden', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 9 },
})
