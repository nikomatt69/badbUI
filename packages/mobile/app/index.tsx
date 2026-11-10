import { useState } from "react"
import { Text, View, Linking } from "react-native"
import { router } from "expo-router"
import { Game } from "@badb/core"
import { useSession } from "../src/session"
import { Screen, Title, Panel, Button, LoadState, useLoad, styles } from "../src/ui"
export default function Home() {
  const { api, server } = useSession()
  const load = useLoad(server, () => Promise.all([api.home(), api.boss.list(), api.post.list("guide")]))
  const [post, setPost] = useState("")
  const content = useLoad(post, async () => (post ? api.post.get("guide", post) : null))
  const home = load.data?.[0]
  return (
    <Screen>
      <Title label="IL CAMPO BASE, SEMPRE CON TE">Stesso stendardo. Il tuo orario.</Title>
      <LoadState load={load} />
      {home ? (
        <>
          <Text style={styles.text}>{home.guild.motto}</Text>
          <Panel>
            <Text style={styles.heading}>{home.guild.name}</Text>
            <Text style={styles.text}>
              {home.members} membri · {home.characters} personaggi
            </Text>
            <Button title="Il prossimo raid ↗" onPress={() => router.navigate("/raid")} />
            <Button title="Segna quando ci sei" onPress={() => router.navigate("/availability")} />
          </Panel>
          {home.news.map((p) => (
            <Panel key={p.id}>
              <Text style={styles.label}>{p.category || "DIARIO"}</Text>
              <Text style={styles.heading}>{p.title}</Text>
              <Text style={styles.text}>{p.excerpt}</Text>
            </Panel>
          ))}
          {home.guild.discordInvite ? (
            <Button
              title="Apri Discord ↗"
              onPress={() => {
                void Linking.openURL(home.guild.discordInvite)
              }}
            />
          ) : null}
          <Text style={styles.heading}>Guide di gilda</Text>
          {load.data?.[2].map((p) => (
            <Button key={p.id} title={p.title} onPress={() => setPost(p.slug)} />
          ))}
          {post ? (
            <>
              <LoadState load={content} />
              {content.data ? (
                <Panel>
                  <Text style={styles.heading}>{content.data.title}</Text>
                  <Text style={styles.text}>{content.data.body}</Text>
                  <Button title="Chiudi guida" onPress={() => setPost("")} />
                </Panel>
              ) : null}
            </>
          ) : null}
          <Text style={styles.heading}>Boss & tattiche</Text>
          <Text style={styles.tiny}>Valutazioni della gilda, non statistiche ufficiali.</Text>
          {load.data?.[1].map((b) => (
            <Panel key={b.id}>
              <Text style={styles.label}>CONFIDENZA {b.confidence}</Text>
              <Text style={styles.heading}>{b.name}</Text>
              <Text style={styles.text}>{b.notes}</Text>
              {Game.roles.map((role) => (
                <View key={role}>
                  <Text style={styles.label}>{Game.roleLabel[role]}</Text>
                  {b.best[role].map((fit) => (
                    <Text key={`${fit.cls}/${fit.spec}`} style={[styles.text, { color: Game.classes[fit.cls].color }]}>
                      {Game.classes[fit.cls].label} · {Game.findSpec(fit.cls, fit.spec)?.label} /{" "}
                      {fit.score === null ? "—" : Math.round(fit.score)}
                    </Text>
                  ))}
                </View>
              ))}
            </Panel>
          ))}
        </>
      ) : null}
    </Screen>
  )
}
