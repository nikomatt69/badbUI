import { useState } from "react"
import { Text } from "react-native"
import { Game } from "@badb/core"
import { useSession } from "../src/session"
import { Screen, Title, Panel, Button, Input, useAction, styles } from "../src/ui"
export default function Profile() {
  const session = useSession()
  const [server, setServer] = useState(session.server)
  const [code, setCode] = useState("")
  const action = useAction()
  return (
    <Screen>
      <Title label="IL TUO CAMPO BASE">{session.me ? session.me.user.name : "Collega la tua gilda."}</Title>
      {session.me ? (
        <>
          <Panel>
            <Text style={styles.label}>{Game.rankLabel[session.me.user.rank]}</Text>
            <Text style={styles.text}>{session.server}</Text>
            {session.me.characters.map((c) => (
              <Text key={c.id} style={[styles.text, { color: Game.classes[c.cls].color }]}>
                {c.name} · {Game.roleLabel[c.role]} {c.main ? "· Principale" : ""}
              </Text>
            ))}
            <Button
              title="Esci e revoca questa sessione"
              disabled={action.busy}
              onPress={() => {
                void action.run(session.logout, false)
              }}
            />
          </Panel>
          <Text style={styles.text}>
            Gestisci candidature, gruppi e contenuti dal sito della gilda. L’app condivide lo stesso server e lo stesso
            account.
          </Text>
        </>
      ) : (
        <Panel>
          <Text style={styles.text}>
            Dal sito: Profilo → Collega mobile. Inserisci qui il codice monouso. Il token sarà custodito nello storage
            sicuro del dispositivo.
          </Text>
          <Input label="Server della gilda" value={server} set={setServer} placeholder="https://gilda.example.com" />
          <Text style={styles.tiny}>
            Sul telefono usa l’indirizzo del computer nella rete locale durante lo sviluppo; in produzione usa HTTPS.
          </Text>
          <Input label="Codice mobile" value={code} set={setCode} placeholder="ABCDEFGH" />
          <Button
            title="Collega l’app ↗"
            disabled={action.busy || !code.trim()}
            onPress={() => {
              void action.run(() => session.connect(server, code), false)
            }}
          />
        </Panel>
      )}
      {action.message ? (
        <Text accessibilityLiveRegion="polite" style={styles.text}>
          {action.message}
        </Text>
      ) : null}
    </Screen>
  )
}
