# BadbUI Chatbot

An English in-game chatbot with a provider/model top bar, conversation history and a multiline composer. **Add quests** opens the active character's quest log; select quests to attach, click them again to remove, or use **Clear quests**. Level, class, role confidence, zone and quest progress are captured with each question. Bags can be included or excluded.

The AI uses **`@nikcli-ai/sdk-next` 1.428.0 embedded in-process**, not a CLI subprocess or a remote nikcli server. WoW itself only runs Lua and has no Internet API. The chat UI, quest picker and settings are in the addon; the local runtime performs model inference and nikcli `websearch`/`webfetch` outside the game. It is independent of the guild companion and needs no guild login.

## Start

Install the updated addon, then from this repository:

```sh
bun install
bun run chat:dev --wow "/path/to/World of Warcraft/_forever_" --account "YOUR-WTF-ACCOUNT"
```

For the packaged runtime, extract `BadbUI-Chatbot-0.3.0.zip`, run `bun install` in its folder, then:

```sh
bun chat.mjs --wow "/path/to/World of Warcraft/_forever_" --account "YOUR-WTF-ACCOUNT"
```

The private nikcli instance defaults to `~/.config/badb/wow-chat`; use `--runtime` to override it. The runtime uses nikcli's normal credential store and provider APIs. Keep only one runtime active for a given addon. A lock prevents two processes using the same runtime directory. After an unexpected crash, check that the process stopped before removing its `bridge.lock` directory.

## In WoW

1. Open **Chatbot** in `/badb`, or type `/badb chat`.
2. Use **Check replies · reload** to load nikcli's provider/model catalog.
3. Choose a connected provider and model in the top bar, plus an available reasoning variant.
4. Use **Settings** to connect/disconnect a provider, start/complete a supported OAuth flow, refresh the catalog, or edit nikcli's advanced JSON configuration.
5. Type a question, attach relevant quests with **+ Add quests**, and choose whether to include bags.
6. Click **Send & reload**. Wait for **Reply ready** in the local runtime, then click **Check replies · reload** to read the answer and source URLs.

Two reloads are required: WoW writes SavedVariables on the first and loads the generated response file on the second. This is not a live streaming connection. A runtime reply written during a reload may require another reload to appear. OAuth sign-in may require visiting the provider's URL in a browser; leave the runtime running so its pending login survives.

## Providers, models and research

The provider/model catalog and OAuth methods come from the embedded SDK, not a hard-coded list. Providers already connected to nikcli can be selected. Advanced config is a JSON merge using nikcli's configuration schema: custom provider endpoints/models, model defaults, web search backends, temperature and other agent settings. For WoW-specific temperature/options, edit `agent.wow-assistant`. The harness keeps its research-only permission rules, system instructions and disabled sharing/snapshots.

For example, set search to Exa (the nikcli default), Parallel, or a custom MCP search endpoint using `websearch.provider`, `websearch.apiKey`, `websearch.url`, and `websearch.tool`. The runtime enables nikcli's search feature gate for third-party models as well. The model should support tool calling to research effectively.

Quest answers are prompted to search Wowhead by quest ID and distinguish Classic/Forever from Retail. The harness records actual successful search/fetch URLs. If no websearch completes, the answer is explicitly marked unverified. Wowhead is a source, not a bundled database or an official integration; access or search-provider quotas can fail. A Classic source does not prove Forever mechanics are identical.

## Local data

The runtime reads `WTF/Account/<account>/SavedVariables/BadbUI.lua` as data, never executes it and never modifies it. It writes `Interface/AddOns/BadbUI/Data/ChatbotSync.lua` atomically. It sends only the question and attached game snapshot to the selected model provider; search queries go to the configured search backend. It does not scan arbitrary PC files. Conversations are isolated by character identity and conversation generation.

API keys entered in-game must pass through the local SavedVariables queue because WoW has no network API. The UI masks the field, and replies never contain keys. After acknowledgement, reload again to clear the pending secret from memory and the next saved file. WoW's `.bak` backups may retain previous values: do not share those files. Prefer existing nikcli credentials or OAuth when possible. Advanced config displays omit secret fields; omitted fields preserve their existing values.

Replies and error receipts are persisted and deduplicated across runtime restarts. The response bundle also restores questions and replies on Forever builds that fail to restore SavedVariables. A crash during an in-flight model call cannot guarantee exactly-once billing. Failed requests stay visible in chat and can be retried. Unknown API data and uncached items are marked incomplete rather than reported as absent. Requests are blocked during combat.

## Verification

```sh
bun run --cwd packages/wow-chat typecheck
bun run --cwd packages/wow-chat test
bun run --cwd packages/wow-chat test:embedded
bun run test:addon
```

The embedded integration check uses the real SDK with synthetic localhost model/search services, no paid model or player account. It checks provider discovery, the character prompt, the actual websearch call and returned source URL. Lua tests cover the in-game controls, quest attachment, context, combat guards and character isolation. Visual layout and client API compatibility still need an in-game check on Forever.
