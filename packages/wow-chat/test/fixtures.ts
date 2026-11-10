import type { ChatRequest } from "../src/protocol"

export function request(id = "request-1", character = "Player-1"): Extract<ChatRequest, { kind: "ask" }> {
  return {
    id,
    character,
    at: Math.floor(Date.now() / 1000),
    generation: 1,
    kind: "ask",
    payload: {
      text: "Where do I go?",
      provider: "test",
      model: "test-model",
      context: {
        character,
        capturedAt: Math.floor(Date.now() / 1000),
        client: { flavor: "WoW Forever", interface: 16001 },
        player: { level: 23, zone: "Westfall" },
        quests: [
          {
            key: "12",
            id: 12,
            title: "The People's Militia",
            selected: true,
            objectives: [{ text: "Defias: 2/10", have: 2, need: 10 }],
          },
        ],
        questsComplete: true,
        bags: [{ id: 123, count: 4, bag: 0, slot: 1 }],
        bagsIncluded: true,
        bagsComplete: true,
      },
    },
  }
}
