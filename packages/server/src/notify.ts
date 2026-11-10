/** Solo il server possiede l'URL del webhook. Nessuna menzione iniettata dai contenuti. */
export async function announce(url: string, text: string) {
  if (!url) return
  await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ content: text.slice(0, 1800), allowed_mentions: { parse: [] } }),
    signal: AbortSignal.timeout(5000),
  })
    .then((response) => {
      if (!response.ok) console.error(`Annuncio Discord: HTTP ${response.status}`)
    })
    .catch(() => {
      console.error("Annuncio Discord non consegnato")
    })
}
