import { useEffect, useState, type ReactNode } from "react"
import {
  ScrollView,
  Text,
  View,
  Pressable,
  TextInput,
  StyleSheet,
  ActivityIndicator,
  RefreshControl,
} from "react-native"
import { useSession } from "./session"
export const colors = {
  bg: "#10130f",
  panel: "#1c2118",
  line: "#414a31",
  text: "#ebe5d4",
  muted: "#a5ac94",
  accent: "#c7d58a",
  gold: "#b89858",
}
export const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.bg },
  content: { padding: 22, paddingBottom: 50, gap: 18 },
  title: { fontFamily: "Cinzel", fontSize: 30, lineHeight: 40, color: colors.text },
  heading: { fontFamily: "Cinzel", fontSize: 21, lineHeight: 30, color: colors.text, marginBottom: 8 },
  text: { fontFamily: "Plex", fontSize: 14, lineHeight: 23, color: colors.muted },
  label: { color: colors.gold, fontSize: 10, letterSpacing: 2, marginBottom: 10 },
  panel: { padding: 20, borderWidth: 1, borderColor: colors.line, backgroundColor: colors.panel, gap: 12 },
  row: { flexDirection: "row", flexWrap: "wrap", gap: 9, alignItems: "center" },
  button: {
    padding: 13,
    minHeight: 46,
    borderColor: colors.line,
    borderWidth: 1,
    backgroundColor: "#28321d",
    justifyContent: "center",
    alignItems: "center",
  },
  buttonText: { fontFamily: "Plex", color: colors.accent, fontSize: 13 },
  input: {
    fontFamily: "Plex",
    fontSize: 16,
    minHeight: 48,
    padding: 12,
    backgroundColor: colors.bg,
    borderWidth: 1,
    borderColor: colors.line,
    color: colors.text,
  },
  error: { color: "#e8b89f", fontFamily: "Plex", fontSize: 13, lineHeight: 21 },
  rule: { borderBottomWidth: 1, borderColor: colors.line, paddingVertical: 10 },
  tiny: { fontFamily: "Plex", fontSize: 11, color: colors.muted },
})
export function Button({ title, onPress, disabled }: { title: string; onPress: () => void; disabled?: boolean }) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [styles.button, { opacity: disabled ? 0.4 : pressed ? 0.65 : 1 }]}
    >
      <Text style={styles.buttonText}>{title}</Text>
    </Pressable>
  )
}
export function Input({
  label,
  value,
  set,
  placeholder,
  secure,
}: {
  label: string
  value: string
  set: (s: string) => void
  placeholder?: string
  secure?: boolean
}) {
  return (
    <View style={{ gap: 6 }}>
      <Text style={styles.text}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        value={value}
        onChangeText={set}
        style={styles.input}
        placeholder={placeholder}
        placeholderTextColor="#788268"
        autoCapitalize="none"
        secureTextEntry={secure}
        autoCorrect={false}
      />
    </View>
  )
}
export function Screen({ children }: { children: ReactNode }) {
  const { ready, error, refresh } = useSession()
  const [loading, setLoading] = useState(false)
  const [failure, setFailure] = useState("")
  return (
    <ScrollView
      style={styles.page}
      contentContainerStyle={styles.content}
      contentInsetAdjustmentBehavior="automatic"
      keyboardShouldPersistTaps="handled"
      refreshControl={
        <RefreshControl
          tintColor={colors.accent}
          refreshing={loading}
          onRefresh={() => {
            setLoading(true)
            refresh()
              .catch((e: Error) => setFailure(e.message))
              .finally(() => setLoading(false))
          }}
        />
      }
    >
      {!ready ? <ActivityIndicator color={colors.accent} /> : children}
      {error ? <Text style={styles.error}>{error}</Text> : null}
      {failure ? <Text style={styles.error}>{failure}</Text> : null}
    </ScrollView>
  )
}
export function Panel({ children }: { children: ReactNode }) {
  return <View style={styles.panel}>{children}</View>
}
export function Title({ label, children }: { label: string; children: ReactNode }) {
  return (
    <View>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.title}>{children}</Text>
    </View>
  )
}
export function useLoad<T>(key: string, fetcher: () => Promise<T>) {
  const { revision } = useSession()
  const [data, setData] = useState<T>()
  const [error, setError] = useState("")
  const [retry, setRetry] = useState(0)
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    let active = true
    setError("")
    setLoading(true)
    fetcher()
      .then((result) => {
        if (active) setData(result)
      })
      .catch((e: Error) => {
        if (active) setError(e.message)
      })
      .finally(() => {
        if (active) setLoading(false)
      })
    return () => {
      active = false
    }
  }, [key, revision, retry])
  return { data, error, loading, retry: () => setRetry((n) => n + 1) }
}
export function LoadState({ load }: { load: { error: string; loading: boolean; retry: () => void } }) {
  return load.loading ? (
    <ActivityIndicator color={colors.accent} />
  ) : load.error ? (
    <Panel>
      <Text style={styles.error}>{load.error}</Text>
      <Button title="Riprova" onPress={load.retry} />
    </Panel>
  ) : null
}
export function useAction() {
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState("")
  const { refresh } = useSession()
  const run = async (fn: () => Promise<unknown>, reload = true) => {
    if (busy) return
    setBusy(true)
    setMessage("")
    try {
      await fn()
      if (reload) await refresh()
      setMessage("Aggiornato.")
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Operazione non riuscita")
    } finally {
      setBusy(false)
    }
  }
  return { busy, message, run }
}
