import * as Haptics from 'expo-haptics'
import * as ImagePicker from 'expo-image-picker'
import { manipulateAsync, SaveFormat } from 'expo-image-manipulator'
import { useState } from 'react'
import { ActivityIndicator, Image, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, useWindowDimensions, View } from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { t } from '../../ui/i18n.ts'
import { ArrowUpIcon, CloseIcon, PlusIcon, StopIcon } from '../../ui/icons.tsx'
import { Glass, GlassControl } from '../../ui/glass.tsx'
import { concentricInset, radius, screenRadius, type as typeScale, type Palette } from '../../ui/tokens.ts'

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

// zen's composer geometry: one resting capsule that shares the display corner's
// centre (inset = R - h/2), and an editing card that grows from 124 up to 46% of
// the screen with a 52pt control bar. Attachments live inside the card.
const LINE = 22
const RESTING = Math.max(50, LINE + 20) + 12
const EDITING = 124
const TEXT_TOP = 14
const BAR = 52
const EDGE = 16
const EDITING_BOTTOM = 12
const MEDIA = 80
const MIN_TEXT = 120

export function Composer({ name, running, canStop, canAttach, onSend, onStop, onHeight, p }: {
  name: string; running: boolean; canStop: boolean; canAttach: boolean
  onSend: (text: string, photos: Photo[]) => Promise<void>; onStop: () => void; onHeight?: (height: number) => void; p: Palette
}) {
  const [text, setText] = useState('')
  const [photos, setPhotos] = useState<Photo[]>([])
  const [preparing, setPreparing] = useState(false)
  const [pickError, setPickError] = useState<string | null>(null)
  const [focused, setFocused] = useState(false)
  const [textHeight, setTextHeight] = useState(LINE)
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
  // Resting is the empty, unfocused state; anything typed keeps the card open.
  const expanded = focused || text !== '' || photos.length > 0
  const media = photos.length > 0 || preparing ? MEDIA : 0
  const available = windowHeight - insets.top
  const cap = Math.min(available - 12, Math.max(available * 0.46, TEXT_TOP + BAR + LINE))
  const height = expanded ? Math.min(cap, Math.max(EDITING, TEXT_TOP + media + textHeight + BAR)) : RESTING
  const corner = expanded ? 26 : RESTING / 2
  // Concentric only while resting: an editing card returns to the standard margins.
  const screenR = screenRadius(insets.bottom, Platform.OS)
  const tight = concentricInset(screenR, RESTING)
  const fits = screenWidth - 2 * tight - 88 >= MIN_TEXT
  const android = Platform.OS === 'android'
  const inset = android ? 12 : expanded ? EDGE : fits ? tight : EDGE
  const bottom = android ? Math.max(insets.bottom, 10) : expanded ? EDITING_BOTTOM : concentricInset(screenR, RESTING)
  const stop = running && canStop && !ready
  return (
    <View style={{ paddingBottom: bottom }} onLayout={event => onHeight?.(event.nativeEvent.layout.height)}>
      {pickError !== null ? <Text style={[typeScale.small, { color: p.danger, textAlign: 'center', marginBottom: 4 }]}>{pickError}</Text> : null}
      <Glass radius={corner} style={{ marginHorizontal: inset, height }} contentStyle={styles.cardIn}>
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
        {expanded ? (
          <>
            <TextInput value={text} onChangeText={setText} placeholder={t('Message {name}', { name })} placeholderTextColor={p.ink3}
              multiline scrollEnabled onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
              onContentSizeChange={event => setTextHeight(event.nativeEvent.contentSize.height)}
              style={[styles.text, { color: p.ink }]} accessibilityLabel={t('Message {name}', { name })} />
            <View style={styles.bar}>
              {canAttach
                ? <Pressable accessibilityRole="button" accessibilityLabel={t('Add photos')} onPress={() => void pick()} hitSlop={2} style={styles.hit}>
                    <PlusIcon size={22} color={p.ink2} />
                  </Pressable>
                : <View style={styles.hit} />}
              {stop
                ? <GlassControl label={t('Stop')} onPress={onStop}><StopIcon size={24} /></GlassControl>
                : <GlassControl label={t('Send')} accent disabled={!ready} onPress={send}><ArrowUpIcon size={24} /></GlassControl>}
            </View>
          </>
        ) : (
          <View style={styles.row}>
            {canAttach
              ? <Pressable accessibilityRole="button" accessibilityLabel={t('Add photos')} onPress={() => void pick()} hitSlop={2} style={styles.hit}>
                  <PlusIcon size={22} color={p.ink2} />
                </Pressable>
              : null}
            <TextInput value={text} onChangeText={setText} placeholder={t('Message {name}', { name })} placeholderTextColor={p.ink3}
              multiline onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
              style={[styles.resting, { color: p.ink }]} accessibilityLabel={t('Message {name}', { name })} />
            {stop
              ? <GlassControl label={t('Stop')} onPress={onStop}><StopIcon size={24} /></GlassControl>
              : <GlassControl label={t('Send')} accent disabled={!ready} onPress={send}><ArrowUpIcon size={24} /></GlassControl>}
          </View>
        )}
      </Glass>
    </View>
  )
}

const styles = StyleSheet.create({
  cardIn: { alignItems: 'stretch' },
  media: { flexGrow: 0 },
  photos: { gap: 8, paddingHorizontal: 9, paddingTop: 9 },
  photo: { width: 64, height: 64, borderRadius: 12 },
  unpick: { position: 'absolute', top: -5, right: -5, width: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', flexGrow: 1, paddingHorizontal: 9 },
  hit: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  resting: { flex: 1, fontSize: 16, lineHeight: LINE, paddingVertical: 10, paddingHorizontal: 3 },
  text: { flexGrow: 1, fontSize: 16, lineHeight: LINE, paddingTop: TEXT_TOP, paddingHorizontal: 12 },
  bar: { height: BAR, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 9 },
})
