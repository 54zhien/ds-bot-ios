import { createNativeStackNavigator } from '@react-navigation/native-stack'
import { useNavigation, type NavigationProp, type ParamListBase } from '@react-navigation/native'
import { useEffect, useRef, useState } from 'react'
import { ActivityIndicator, Dimensions, Modal, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import * as SecureStore from 'expo-secure-store'
import { onPrefsChange, readPrefs } from '../store.ts'
import { Drawer, useDrawer } from './Drawer.tsx'
import { useTeam } from '../team/context.tsx'
import { t } from '../ui/i18n.ts'
import { screenRadius, shadow, type as typeScale, useTheme } from '../ui/tokens.ts'
import { GlassCluster, GlassControl, GlassPill } from '../ui/glass.tsx'
import { Avatar, RoomAvatar } from '../ui/marks.tsx'
import { GearIcon, PeopleIcon, PlusIcon, SearchIcon, SidebarIcon, SideIcon } from '../ui/icons.tsx'
import { ChatView, prefetchChat } from '../screens/Chat.tsx'
import { NeedsYou } from '../screens/NeedsYou.tsx'
import { Settings } from '../screens/Settings.tsx'
import { TeamList, type ChatTarget } from '../screens/TeamList.tsx'
import { BotDetails, BotEdit, NewBot, NewGroup, GroupDetails, GroupSettings, Memory, Schedules, Folder, Usage, Computers, Secrets } from '../screens/manage.tsx'
import { Providers, Connectors, Capabilities, TeamUsage, Location, Updates, About } from '../screens/settings-pages.tsx'
import { Side } from '../screens/side.tsx'
import { BotBrowser } from '../screens/manage.tsx'
import type { Bot, Room } from '../connection.ts'
import { pendingCountOf } from './pending.ts'
import { activeChatTarget, openChat } from './open-chat.ts'
import { Sheet, SheetHeader } from './sheet.tsx'

const Stack = createNativeStackNavigator()
const LAST_KEY = 'dsbot.lastChat'

// Drawer content = the desktop sidebar as a drawer: "Needs you" row on top when
// anything is pending, the team list, and a footer with the You mark + gear.
function DrawerContent() {
  const { p } = useTheme()
  const { team } = useTeam()
  const insets = useSafeAreaInsets()
  const navigation = useNavigation<NavigationProp<ParamListBase>>()
  const drawer = useDrawer()
  const pending = pendingCountOf(team)
  const fallbackId = (team?.bots?.find(b => b.id === team?.mainBotId) ?? team?.bots?.[0])?.id
  const [searching, setSearching] = useState(false)
  const [query, setQuery] = useState('')
  const [newOpen, setNewOpen] = useState(false)
  // The gear sits concentric with the display corner, like the composer: its
  // centre is R from both edges, so the panel and the control share a centre.
  const gearInset = Math.max(16, screenRadius(insets.bottom, Platform.OS) - 22)
  const create = (screen: 'NewBot' | 'NewGroup') => { setNewOpen(false); drawer.close(); navigation.navigate(screen) }
  // The chat on screen is marked in the list, as the desktop marks its open chat. The
  // drawer sits outside the navigator, so it follows the container's own state.
  const [current, setCurrent] = useState<string | undefined>(undefined)
  useEffect(() => {
    const update = () => setCurrent(activeChatTarget(navigation.getState(), fallbackId)?.id)
    update()
    return navigation.addListener('state', update)
  }, [navigation, fallbackId])
  // A chat replaces the one on screen; nothing stays stacked under it. Needs you and
  // Settings slide up over the chat and go back down to it.
  const open = (target: ChatTarget | { kind: 'needs' } | { kind: 'settings' }) => {
    drawer.close()
    if (target.kind === 'needs') navigation.navigate('Needs')
    else if (target.kind === 'settings') navigation.navigate('Settings')
    else openChat(navigation, target)
  }
  return (
    <View style={{ flex: 1, backgroundColor: p.sidebar }}>
      {/* The desktop sidebar's head: the product name, search and New. */}
      <GlassCluster style={[styles.drawerHead, { paddingTop: insets.top + 6 }]}>
        <Text style={{ color: p.ink, fontSize: 17, fontWeight: '600', flex: 1 }}>DS Bot</Text>
        <GlassControl label={t('Search')} onPress={() => setSearching(on => !on)}>
          <SearchIcon size={24} color={p.ink2} />
        </GlassControl>
        <GlassControl label={t('New')} onPress={() => setNewOpen(true)}>
          <PlusIcon size={24} color={p.ink2} />
        </GlassControl>
      </GlassCluster>
      {searching ? (
        <GlassPill height={44} style={{ marginHorizontal: 16, marginBottom: 8 }}>
          <SearchIcon size={20} color={p.ink3} />
          <TextInput value={query} onChangeText={setQuery} placeholder={t('Search the team')} placeholderTextColor={p.ink3} autoFocus
            style={{ flex: 1, fontSize: 15, paddingVertical: 4, color: p.ink }} autoCapitalize="none" autoCorrect={false} />
        </GlassPill>
      ) : null}
      {pending > 0 ? (
        <Pressable accessibilityRole="button" onPress={() => open({ kind: 'needs' })}
          style={({ pressed }) => [styles.needsRow, { backgroundColor: pressed ? p.hover : 'transparent' }]}>
          <Text style={[typeScale.rowName, { color: p.accent, flex: 1 }]}>{t('Needs you')}</Text>
          <View style={[styles.badge, { backgroundColor: p.accent }]}><Text style={{ color: p.accentInk, fontSize: 12, fontWeight: '600' }}>{pending}</Text></View>
        </Pressable>
      ) : null}
      <View style={{ flex: 1 }}>
        <TeamList onOpen={open} query={searching ? query : ''} current={current} />
      </View>
      <Modal visible={newOpen} transparent animationType="fade" onRequestClose={() => setNewOpen(false)}>
        <Pressable style={styles.sheetScrim} onPress={() => setNewOpen(false)} accessibilityLabel={t('Close')}>
          <View style={[styles.newSheet, { backgroundColor: p.card, borderColor: p.line, marginBottom: insets.bottom + 12 }, shadow(3)]}>
            <Pressable accessibilityRole="button" onPress={() => create('NewBot')} style={({ pressed }) => [styles.newRow, pressed && { backgroundColor: p.hover }]}>
              <View style={[styles.newIcon, { backgroundColor: p.hover }]}><PlusIcon size={18} color={p.ink} /></View>
              <Text style={[typeScale.settingsRow, { color: p.ink }]}>{t('Create new Bot')}</Text>
            </Pressable>
            <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: p.line, marginLeft: 64 }} />
            <Pressable accessibilityRole="button" onPress={() => create('NewGroup')} style={({ pressed }) => [styles.newRow, pressed && { backgroundColor: p.hover }]}>
              <View style={[styles.newIcon, { backgroundColor: p.hover }]}><PeopleIcon size={18} color={p.ink} /></View>
              <Text style={[typeScale.settingsRow, { color: p.ink }]}>{t('Create group chat')}</Text>
            </Pressable>
          </View>
        </Pressable>
      </Modal>
      <View style={[styles.foot, { paddingBottom: gearInset, paddingLeft: gearInset }]}>
        <GlassControl label={t('Settings')} onPress={() => open({ kind: 'settings' })}>
          <GearIcon size={24} color={p.ink2} />
        </GlassControl>
      </View>
    </View>
  )
}

function Pill({ title, bot, room, bots }: { title: string; bot?: Parameters<typeof Avatar>[0]['bot']; room?: Room; bots: Bot[] }) {
  const { p, dark } = useTheme()
  return (
    <GlassPill height={44} style={{ maxWidth: '100%' }}>
      {bot ? <Avatar bot={bot} dark={dark} size={28} ring={p.main} /> : room ? <RoomAvatar room={room} bots={bots} dark={dark} size={28} ring={p.main} /> : null}
      <Text style={{ color: p.ink, fontSize: 15, lineHeight: 20, fontWeight: '500', flexShrink: 1 }} numberOfLines={1}>{title}</Text>
    </GlassPill>
  )
}

function Header({ title, bot, room, bots = [], onMenu, onPill, onSide }: { title: string; bot?: Parameters<typeof Avatar>[0]['bot']; room?: Room; bots?: Bot[]; onMenu: () => void; onPill?: () => void; onSide?: () => void }) {
  const { p } = useTheme()
  const { team, online } = useTeam()
  const pending = pendingCountOf(team) > 0
  const insets = useSafeAreaInsets()
  // The link dropped after the team loaded: the screen keeps what it shows and says so.
  const reconnecting = team !== null && !online
  return (
    // Floats over the list so messages pass under the glass instead of stopping at a line.
    <View pointerEvents="box-none" style={styles.header}>
    <GlassCluster spacing={6} pointerEvents="box-none" style={[styles.headerRow, { paddingTop: insets.top }]}>
      <GlassControl label={t('Open team list')} onPress={onMenu} dot={pending}>
        <SidebarIcon size={26} color={p.ink2} />
      </GlassControl>
      {/* A long group name ends in an ellipsis inside the pill instead of pushing past the side buttons. */}
      <View style={{ flex: 1, alignItems: 'center', minWidth: 0 }}>
        {title === '' ? null
          : bot === undefined && room === undefined ? <Text style={[typeScale.headerTitle, { color: p.ink }]} numberOfLines={1}>{title}</Text>
            : onPill !== undefined ? <Pressable accessibilityRole="button" onPress={onPill} style={{ maxWidth: '100%' }}><Pill title={title} bot={bot} room={room} bots={bots} /></Pressable> : <Pill title={title} bot={bot} room={room} bots={bots} />}
      </View>
      {onSide !== undefined ? (
        <GlassControl label={t('Side chat')} onPress={onSide}>
          <SideIcon size={26} color={p.ink2} />
        </GlassControl>
      ) : <View style={{ width: 44, height: 44 }} />}
    </GlassCluster>
    {reconnecting ? (
      <View pointerEvents="none" style={{ alignItems: 'center', paddingBottom: 6 }} accessibilityRole="alert">
        <GlassPill height={30} style={{ paddingHorizontal: 0 }}>
          <ActivityIndicator size="small" color={p.ink3} />
          <Text style={[typeScale.caption, { color: p.ink3 }]}>{t('Reconnecting…')}</Text>
        </GlassPill>
      </View>
    ) : null}
    </View>
  )
}

function ChatScreenB({ route, navigation }: any) {
  const { team, error, linked, call, computer } = useTeam()
  const { p, dark } = useTheme()
  const drawer = useDrawer()
  const params = route.params as ChatTarget | undefined
  // On launch the saved chat is read while the team state is still on its way.
  useEffect(() => { if (linked === true && team === null && params !== undefined) prefetchChat(call, computer?.hostDeviceId ?? '', params) }, [linked, team === null])
  useEffect(() => { if (params) void SecureStore.setItemAsync(LAST_KEY, JSON.stringify(params)) }, [params])
  const fallback = team?.bots?.find(b => b.id === team?.mainBotId) ?? team?.bots?.[0]
  const kind = params?.kind ?? 'bot'
  const id = params?.id ?? fallback?.id ?? ''
  const bot = kind === 'bot' ? team?.bots?.find(b => b.id === id) : undefined
  const room = kind === 'room' ? team?.rooms?.find(r => r.id === id) : undefined
  // A saved chat that the team no longer has is dropped and falls back to the
  // first Main Bot instead of opening an empty screen.
  const missing = team !== null && params !== undefined && ((kind === 'bot' && bot === undefined) || (kind === 'room' && room === undefined))
  useEffect(() => {
    if (!missing) return
    void SecureStore.deleteItemAsync(LAST_KEY)
    if (fallback !== undefined) navigation.setParams({ kind: 'bot', id: fallback.id })
  }, [missing])
  const header = <Header title={bot?.name ?? room?.name ?? ''} bot={bot} room={room} bots={team?.bots ?? []} onMenu={() => drawer.open()} onPill={() => { if (bot) navigation.navigate('BotDetails', { botId: bot.id }); else if (room) navigation.navigate('GroupDetails', { roomId: room.id }) }} onSide={bot !== undefined && bot.sessionId !== undefined ? () => navigation.navigate('Side', { bot, sessionId: bot.sessionId }) : undefined} />
  if (team === null) return (
    <View style={{ flex: 1, backgroundColor: p.main }}>
      {header}
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 12 }}>
        <ActivityIndicator color={p.accent} />
        <Text style={[typeScale.caption, { color: p.ink3, textAlign: 'center' }]}>{error ?? t('Connecting…')}</Text>
        <Pressable accessibilityRole="button" onPress={() => navigation.navigate('Settings', { screen: 'Computers', initial: false })} hitSlop={8} style={{ minHeight: 44, justifyContent: 'center' }}>
          <Text style={[typeScale.caption, { color: p.accent }]}>{t('Computers')}</Text>
        </Pressable>
      </View>
    </View>
  )
  const onMissing = () => { void SecureStore.deleteItemAsync(LAST_KEY); if (fallback !== undefined) navigation.setParams({ kind: 'bot', id: fallback.id }) }
  return <ChatView key={`${computer?.hostDeviceId ?? ''}:${kind}:${id}`} bot={bot} room={room} header={header} onMissing={onMissing} />
}

function NeedsSheet({ navigation }: any) {
  return (
    <Sheet>
      <SheetHeader title={t('Needs you')} right={{ label: t('Done'), onPress: () => navigation.goBack(), strong: true }} />
      <NeedsYou onOpen={target => openChat(navigation, target)} />
    </Sheet>
  )
}

// Settings is a sheet with its own pages: they open inside it, and Done takes the
// whole sheet down to the chat underneath.
const SettingsStack = createNativeStackNavigator()
function SettingsHome({ navigation }: any) {
  return (
    <View style={{ flex: 1 }}>
      <SheetHeader title={t('Settings')} right={{ label: t('Done'), onPress: () => navigation.getParent()?.goBack(), strong: true }} />
      <Settings navigation={navigation} />
    </View>
  )
}
function SettingsSheet() {
  const { p } = useTheme()
  return (
    <Sheet>
      <SettingsStack.Navigator screenOptions={{ headerShown: false, contentStyle: { backgroundColor: p.main }, animation: Platform.OS === 'android' ? 'slide_from_right' : 'default' }}>
        <SettingsStack.Screen name="SettingsHome" component={SettingsHome} />
        <SettingsStack.Screen name="Computers" component={Computers} />
        <SettingsStack.Screen name="Secrets" component={Secrets} />
        <SettingsStack.Screen name="Providers" component={Providers} />
        <SettingsStack.Screen name="Connectors" component={Connectors} />
        <SettingsStack.Screen name="Capabilities" component={Capabilities} />
        <SettingsStack.Screen name="TeamUsage" component={TeamUsage} />
        <SettingsStack.Screen name="Location" component={Location} />
        <SettingsStack.Screen name="Updates" component={Updates} />
        <SettingsStack.Screen name="About" component={About} />
        <SettingsStack.Screen name="Folder" component={Folder} />
      </SettingsStack.Navigator>
    </Sheet>
  )
}

// A question or approval that lands while the app is open shows as a banner at
// the top; a tap opens the chat it belongs to.
function NoticeBanner() {
  const { p } = useTheme()
  const { team, onFeed } = useTeam()
  const navigation = useNavigation<NavigationProp<ParamListBase>>()
  const insets = useSafeAreaInsets()
  const [notice, setNotice] = useState<{ text: string; target: ChatTarget; seq: number } | null>(null)
  const banners = useRef(true)
  const fallbackRef = useRef<string | undefined>(undefined)
  fallbackRef.current = (team?.bots?.find(b => b.id === team?.mainBotId) ?? team?.bots?.[0])?.id
  useEffect(() => {
    const read = () => void readPrefs().then(prefs => { banners.current = prefs.banners !== 'off' })
    read()
    return onPrefsChange(read)
  }, [])
  useEffect(() => {
    if (onFeed === undefined) return
    let seq = 0
    return onFeed((event, data) => {
      if (event !== 'notice' || (data?.kind !== 'question' && data?.kind !== 'approval') || !banners.current) return
      const target: ChatTarget = data.roomId !== undefined && data.roomId !== null
        ? { kind: 'room', id: data.roomId }
        : { kind: 'bot', id: data.botId ?? '' }
      // The chat on screen already shows its own card.
      const active = activeChatTarget(navigation.getState(), fallbackRef.current)
      if (active?.kind === target.kind && active.id === target.id) return
      const mine = ++seq
      setNotice({ text: data.title !== undefined ? `${data.title}：${data.text ?? ''}` : (data.text ?? ''), target, seq: mine })
      setTimeout(() => setNotice(current => (current?.seq === mine ? null : current)), 8000)
    })
  }, [onFeed, navigation])
  if (notice === null) return null
  return (
    <Pressable accessibilityRole="button" onPress={() => { openChat(navigation, notice.target); setNotice(null) }}
      style={[{ position: 'absolute', top: insets.top + 8, left: 12, right: 12, zIndex: 10, borderRadius: 12, paddingHorizontal: 14, paddingVertical: 10, backgroundColor: p.card, borderColor: p.accent, borderWidth: 1 }, shadow(2)]}>
      <Text style={[typeScale.small, { color: p.ink }]} numberOfLines={2}>{notice.text}</Text>
    </Pressable>
  )
}

// The chat is the base. Details of a Bot or group push in from the side, with a
// back button and the back swipe; Settings, Needs you and the two Create forms slide
// up as sheets with Done or Cancel.
const PUSH = Platform.OS === 'android' ? 'slide_from_right' as const : 'default' as const
const RISE = Platform.OS === 'android' ? 'slide_from_bottom' as const : 'default' as const
function Inner({ initial }: { initial: ChatTarget | null }) {
  const { p } = useTheme()
  // iOS 26 blurs what scrolls under the glass bar, and sheets come from the system.
  return (
    <View style={{ flex: 1 }}>
    <NoticeBanner />
    {/* scrollEdgeEffects needs a native navigation bar to attach to; with headerShown false and a drawn header it draws nothing, and the Fade layers do that job. */}
    <Stack.Navigator initialRouteName="Chat" screenOptions={{ headerShown: false, animation: PUSH, contentStyle: { backgroundColor: p.main }, scrollEdgeEffects: { top: 'soft', bottom: 'soft', left: 'soft', right: 'soft' } }}>
      <Stack.Screen name="Chat" component={ChatScreenB} initialParams={initial ?? undefined} />
      <Stack.Screen name="BotDetails" component={BotDetails} />
      <Stack.Screen name="BotEdit" component={BotEdit} />
      <Stack.Screen name="GroupDetails" component={GroupDetails} />
      <Stack.Screen name="GroupSettings" component={GroupSettings} />
      <Stack.Screen name="Memory" component={Memory} />
      <Stack.Screen name="Schedules" component={Schedules} />
      <Stack.Screen name="Folder" component={Folder} />
      <Stack.Screen name="Usage" component={Usage} />
      <Stack.Screen name="BotBrowser">{({ route, navigation }: any) => <BotBrowser bot={route.params.bot} navigation={navigation} />}</Stack.Screen>
      <Stack.Screen name="Side">{({ route, navigation }: any) => <Side bot={route.params.bot} sessionId={route.params.sessionId} navigation={navigation} />}</Stack.Screen>
      <Stack.Group screenOptions={{ presentation: Platform.OS === 'ios' ? 'formSheet' : 'modal', animation: RISE, sheetGrabberVisible: true, sheetAllowedDetents: [1] }}>
        <Stack.Screen name="Settings" component={SettingsSheet} />
        <Stack.Screen name="Needs" component={NeedsSheet} options={{ sheetAllowedDetents: [0.55, 1] }} />
        <Stack.Screen name="NewBot" component={NewBot} />
        <Stack.Screen name="NewGroup" component={NewGroup} />
      </Stack.Group>
    </Stack.Navigator>
    </View>
  )
}

export default function ShellB() {
  const { p } = useTheme()
  const width = Math.min(Dimensions.get('window').width * 0.85, 340)
  // Render the navigator only once the saved chat is known, so it can start on it.
  const [saved, setSaved] = useState<ChatTarget | null | undefined>(undefined)
  useEffect(() => {
    void SecureStore.getItemAsync(LAST_KEY).then(text => {
      try { setSaved(text === null ? null : JSON.parse(text) as ChatTarget) } catch { setSaved(null) }
    })
  }, [])
  // The left edge swipe is the iOS back gesture on pushed screens, so the
  // drawer only claims it while the root Chat is on top. The shell sits
  // outside the navigator, so it tracks the top route through the container's
  // own navigation object instead of useNavigationState.
  const navigation = useNavigation<NavigationProp<ParamListBase>>()
  const [top, setTop] = useState('Chat')
  useEffect(() => {
    const update = () => {
      const state = navigation.getState()
      setTop(state?.routes?.[state.index ?? 0]?.name ?? 'Chat')
    }
    update()
    return navigation.addListener('state', update)
  }, [navigation])
  if (saved === undefined) return <View style={{ flex: 1, backgroundColor: p.main }} />
  return (
    <Drawer width={width} content={<DrawerContent />} edgeEnabled={top === 'Chat'}>
      <Inner initial={saved} />
    </Drawer>
  )
}

const styles = StyleSheet.create({
  needsRow: { flexDirection: 'row', alignItems: 'center', marginHorizontal: 12, marginBottom: 4, borderRadius: 10, paddingHorizontal: 12, height: 44 },
  badge: { minWidth: 22, height: 22, borderRadius: 11, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6 },
  foot: { flexDirection: 'row', alignItems: 'center' },
  drawerHead: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 16, paddingBottom: 10 },
  header: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 10 },
  headerRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingBottom: 8, paddingHorizontal: 16 },
  you: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 4, height: 44 },
  sheetScrim: { flex: 1, backgroundColor: 'rgba(0,0,0,0.25)', justifyContent: 'flex-end' },
  newSheet: { marginHorizontal: 12, borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, overflow: 'hidden' },
  newRow: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 56, paddingHorizontal: 14 },
  newIcon: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
})
