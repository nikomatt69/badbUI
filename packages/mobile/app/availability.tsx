import { useState, useEffect } from "react"
import { Text, View, Pressable } from "react-native"
import { Availability, Game } from "@badb/core"
import { useSession } from "../src/session"
import { Screen, Title, Panel, Button, Input, LoadState, useLoad, useAction, styles, colors } from "../src/ui"
export default function Week() {
  const { api, server, me } = useSession()
  const [week, setWeek] = useState(Availability.currentWeek(new Date(), "Europe/Rome"))
  const [mask, setMask] = useState("0".repeat(21))
  const [text, setText] = useState("")
  const member = !!me && Game.rankAtLeast(me.user.rank, "member")
  const load = useLoad(`${server}/${week}/${me?.user.id}`, async () => (member ? api.availability.week(week) : null))
  const action = useAction()
  useEffect(() => {
    setMask(load.data?.people.find((p) => p.userId === me?.user.id)?.mask ?? "0".repeat(21))
  }, [load.data, me?.user.id])
  return (
    <Screen>
      <Title label="IL TEMPO È LA NOSTRA RISORSA">Chi c’è?</Title>
      {!member ? (
        <Text style={styles.text}>
          Collega dal profilo un account membro della gilda per aggiornare la disponibilità.
        </Text>
      ) : (
        <>
          <View style={styles.row}>
            <Button title="←" onPress={() => setWeek(Availability.addDays(week, -7))} />
            <Text style={styles.text}>{week}</Text>
            <Button title="→" onPress={() => setWeek(Availability.addDays(week, 7))} />
          </View>
          <LoadState load={load} />
          <Panel>
            {Game.dayShort.map((day, d) => (
              <View style={styles.row} key={day}>
                <Text style={[styles.text, { width: 35 }]}>{day}</Text>
                {Game.slotList.map((slot, s) => {
                  const i = d * 3 + s
                  const selected = mask[i] === "1"
                  return (
                    <Pressable
                      key={slot.id}
                      accessibilityRole="checkbox"
                      accessibilityLabel={`${day} ${slot.label}`}
                      accessibilityState={{ checked: selected }}
                      disabled={action.busy}
                      onPress={() => setMask((m) => m.slice(0, i) + (m[i] === "1" ? "0" : "1") + m.slice(i + 1))}
                      style={[
                        styles.button,
                        { flex: 1, padding: 8, backgroundColor: selected ? colors.accent : colors.bg },
                      ]}
                    >
                      <Text style={{ color: selected ? colors.bg : colors.muted, fontSize: 11 }}>{slot.label}</Text>
                    </Pressable>
                  )
                })}
              </View>
            ))}
            <Button
              title="Salva settimana ↗"
              disabled={action.busy}
              onPress={() => {
                void action.run(() => api.availability.set({ week, ranges: Availability.fromMask(mask) }))
              }}
            />
          </Panel>
          <Panel>
            <Input label="Oppure scrivilo" value={text} set={setText} placeholder="Ci sono mercoledì sera" />
            <Button
              title="Aggiorna dalla frase"
              disabled={action.busy || !text.trim()}
              onPress={() => {
                void action.run(() => api.availability.say(text))
              }}
            />
            <Text style={styles.tiny}>Le frasi senza una settimana esplicita aggiornano quella corrente.</Text>
          </Panel>
          {action.message ? (
            <Text accessibilityLiveRegion="polite" style={styles.text}>
              {action.message}
            </Text>
          ) : null}
          <Text style={styles.heading}>La settimana della gilda</Text>
          {load.data?.people.map((person) => (
            <Panel key={person.userId}>
              <Text style={[styles.heading, { color: person.cls ? Game.classes[person.cls].color : colors.text }]}>
                {person.name}
              </Text>
              {Game.dayShort.map((day, d) => (
                <Text key={day} style={styles.text}>
                  {day} /{" "}
                  {Game.slotList
                    .filter((_, s) => person.mask[d * 3 + s] === "1")
                    .map((s) => s.label)
                    .join(", ") || "—"}
                </Text>
              ))}
            </Panel>
          ))}
        </>
      )}
    </Screen>
  )
}
