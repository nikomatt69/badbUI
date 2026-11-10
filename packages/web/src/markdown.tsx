import { For, type JSX } from "solid-js"
// Sottoinsieme Markdown senza HTML: i dati remoti diventano solo nodi JSX e testo escapato.
function inline(text: string): JSX.Element {
  return text.split(/(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\(https?:\/\/[^\s)]+\))/g).map((part) => {
    if (part.startsWith("**") && part.endsWith("**")) return <strong>{part.slice(2, -2)}</strong>
    if (part.startsWith("`") && part.endsWith("`")) return <code>{part.slice(1, -1)}</code>
    const link = /^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/.exec(part)
    if (link)
      return (
        <a href={link[2]} target="_blank" rel="noreferrer">
          {link[1]} ↗
        </a>
      )
    return part
  })
}
export function Markdown(props: { text: string }) {
  const blocks = () => {
    const result: JSX.Element[] = []
    const lines = props.text.split("\n")
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]!
      if (!line.trim()) continue
      if (line.startsWith("```")) {
        const code = []
        while (++i < lines.length && !lines[i]!.startsWith("```")) code.push(lines[i])
        result.push(
          <pre>
            <code>{code.join("\n")}</code>
          </pre>,
        )
        continue
      }
      const heading = /^(#{1,4})\s+(.+)$/.exec(line)
      if (heading) {
        result.push(heading[1]!.length <= 2 ? <h2>{inline(heading[2]!)}</h2> : <h3>{inline(heading[2]!)}</h3>)
        continue
      }
      if (/^(?:[-*]|\d+\.)\s/.test(line)) {
        const items = [line.replace(/^(?:[-*]|\d+\.)\s+/, "")]
        while (i + 1 < lines.length && /^(?:[-*]|\d+\.)\s/.test(lines[i + 1]!))
          items.push(lines[++i]!.replace(/^(?:[-*]|\d+\.)\s+/, ""))
        result.push(
          <ul>
            <For each={items}>{(item) => <li>{inline(item)}</li>}</For>
          </ul>,
        )
        continue
      }
      const paragraph = [line]
      while (i + 1 < lines.length && lines[i + 1]!.trim() && !/^(#|[-*] |\d+\. |```)/.test(lines[i + 1]!))
        paragraph.push(lines[++i]!)
      result.push(<p>{inline(paragraph.join(" "))}</p>)
    }
    return result
  }
  return <div class="markdown-body">{blocks()}</div>
}
