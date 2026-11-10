import { Text, View } from "react-native"
import { Game } from "@badb/core"
import { useSession } from "../src/session"
import { Screen, Title, Panel, Button, LoadState, useLoad, useAction, styles } from "../src/ui"
export default function Raids() {
  const { api, server, me } = useSession()
  const load = useLoad(server, () => api.event.list())
  const action = useAction()
  return (
    <Screen>
      <Title label="IL PROSSIMO PULL">Un posto nel tuo party.</Title>
      <LoadState load={load} />
      {action.message ? (
        <Text accessibilityLiveRegion="polite" style={styles.text}>
          {action.message}
        </Text>
      ) : null}
      {load.data?.length === 0 ? (
        <Panel>
          <Text style={styles.text}>Nessun raid in programma.</Text>
        </Panel>
      ) : null}
      {load.data?.map((e) => (
        <Panel key={e.id}>
          <Text style={styles.label}>
            {e.group ?? "GILDA"} / {e.status}
          </Text>
          <Text style={styles.heading}>{e.title}</Text>
          <Text style={styles.text}>
            {e.date} · {String(Math.floor(e.start / 60)).padStart(2, "0")}:{String(e.start % 60).padStart(2, "0")} ·
            Europe/Rome
          </Text>
          <Text style={styles.text}>{e.note}</Text>
          <Text style={styles.text}>
            {e.signups.filter((s) => s.status === "yes").length} presenti /{" "}
            {Object.values(e.comp).reduce((a, b) => a + b, 0)} posti
          </Text>
          {e.signups.map((s) => (
            <Text key={s.characterId} style={[styles.text, { color: Game.classes[s.cls].color }]}>
              {s.name} · {Game.roleLabel[s.role]} · {s.status} {s.picked ? "· Titolare" : ""}
            </Text>
          ))}
          {me && Game.rankAtLeast(me.user.rank, "member") && e.status === "open" ? (
            <View style={styles.row}>
              {(
                [
                  ["yes", "Ci sono"],
                  ["maybe", "Forse"],
                  ["no", "Non ci sono"],
                ] as const
              ).map(([status, label]) => (
                <Button
                  key={status}
                  title={label}
                  disabled={action.busy}
                  onPress={() => {
                    void action.run(() => api.event.signup(e.id, { status }))
                  }}
                />
              ))}
            </View>
          ) : null}
        </Panel>
      ))}
    </Screen>
  )
}
