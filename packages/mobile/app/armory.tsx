import { useState } from "react"
import { Text, Linking } from "react-native"
import { Game } from "@badb/core"
import { useSession } from "../src/session"
import { Screen, Title, Panel, Button, Input, LoadState, useLoad, styles } from "../src/ui"
export default function Armory() {
  const { api, server } = useSession()
  const load = useLoad(server, () => api.character.list())
  const [query, setQuery] = useState("")
  const [selected, setSelected] = useState("")
  return (
    <Screen>
      <Title label="LE PERSONE DIETRO IL PARTY">Armory Forever.</Title>
      <Text style={styles.text}>Dati ricevuti dal client di gioco. Le schede manuali sono indicate separatamente.</Text>
      <Input label="Cerca personaggio" value={query} set={setQuery} />
      <LoadState load={load} />
      {load.data
        ?.filter((c) => c.name.toLowerCase().includes(query.toLowerCase()))
        .map((c) => (
          <Panel key={c.id}>
            <Text style={[styles.heading, { color: Game.classes[c.cls].color }]}>{c.name}</Text>
            <Text style={styles.text}>
              Livello {c.level} · {Game.classes[c.cls].label} ·{" "}
              {Game.findSpec(c.cls, c.spec)?.label ?? "Spec non rilevata"}
            </Text>
            <Text style={styles.tiny}>
              {c.source === "addon" ? `Addon Forever · build ${c.client?.build ?? "non registrata"}` : "Scheda manuale"}
              {c.scannedAt ? ` · Scansione ${new Date(c.scannedAt).toLocaleString("it-IT")}` : ""}
            </Text>
            <Button
              title={selected === c.id ? "Chiudi equipaggiamento" : "Equipaggiamento & professioni"}
              onPress={() => setSelected(selected === c.id ? "" : c.id)}
            />
            {selected === c.id ? (
              <>
                {c.gear.length === 0 ? (
                  <Text style={styles.text}>Equipaggiamento non ancora ricevuto dal client.</Text>
                ) : (
                  c.gear.map((item) => (
                    <Text
                      key={item.slot}
                      style={[styles.text, { color: Game.qualityColor[Math.min(item.quality, 5)] }]}
                    >
                      {Game.gearSlots.find((s) => s.id === item.slot)?.label}: {item.name || `Oggetto ${item.id}`}
                      {item.ilvl ? ` · ${item.ilvl}` : ""}
                    </Text>
                  ))
                )}
                {c.professions.map((p) => (
                  <Text key={p.name} style={styles.text}>
                    {p.name} · {p.rank}
                  </Text>
                ))}
              </>
            ) : null}
          </Panel>
        ))}
    </Screen>
  )
}
