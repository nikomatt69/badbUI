// Migrazioni condivise fra SQLite locale e Cloudflare Durable Objects.
export const migrations = [
  `
  CREATE TABLE user (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_key TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    rank TEXT NOT NULL DEFAULT 'guest',
    discord_id TEXT UNIQUE,
    discord_name TEXT,
    created INTEGER NOT NULL
  );
  CREATE TABLE session (
    hash TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    label TEXT NOT NULL DEFAULT '',
    created INTEGER NOT NULL,
    expires INTEGER NOT NULL
  );
  CREATE INDEX session_user ON session(user_id);
  CREATE TABLE link (
    code TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    expires INTEGER NOT NULL
  );
  CREATE TABLE character (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES user(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    name_key TEXT NOT NULL UNIQUE,
    realm TEXT NOT NULL DEFAULT '',
    cls TEXT NOT NULL,
    spec TEXT,
    role TEXT NOT NULL,
    level INTEGER NOT NULL DEFAULT 60,
    race TEXT,
    guild_rank TEXT,
    main INTEGER NOT NULL DEFAULT 0,
    item_level INTEGER,
    gear TEXT NOT NULL DEFAULT '[]',
    professions TEXT NOT NULL DEFAULT '[]',
    in_guild INTEGER NOT NULL DEFAULT 1,
    updated INTEGER NOT NULL,
    source TEXT NOT NULL DEFAULT 'site'
  );
  CREATE INDEX character_user ON character(user_id);
  CREATE TABLE application (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES user(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    cls TEXT NOT NULL,
    spec TEXT,
    role TEXT NOT NULL,
    discord TEXT NOT NULL DEFAULT '',
    experience TEXT NOT NULL DEFAULT '',
    about TEXT NOT NULL DEFAULT '',
    slots TEXT NOT NULL DEFAULT '[]',
    ranges TEXT NOT NULL DEFAULT '[]',
    fee_paid INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    note TEXT NOT NULL DEFAULT '',
    created INTEGER NOT NULL,
    reviewed INTEGER
  );
  CREATE TABLE availability (
    user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    week TEXT NOT NULL,
    ranges TEXT NOT NULL DEFAULT '[]',
    note TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT 'site',
    updated INTEGER NOT NULL,
    PRIMARY KEY (user_id, week)
  );
  CREATE TABLE raid_group (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    slot TEXT NOT NULL,
    raid TEXT NOT NULL,
    days TEXT NOT NULL DEFAULT '[]',
    start INTEGER NOT NULL,
    duration INTEGER NOT NULL DEFAULT 180,
    leader_id TEXT REFERENCES user(id) ON DELETE SET NULL,
    description TEXT NOT NULL DEFAULT '',
    comp TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0
  );
  CREATE TABLE group_member (
    group_id TEXT NOT NULL REFERENCES raid_group(id) ON DELETE CASCADE,
    character_id TEXT NOT NULL REFERENCES character(id) ON DELETE CASCADE,
    bench INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (group_id, character_id)
  );
  CREATE TABLE event (
    id TEXT PRIMARY KEY,
    group_id TEXT REFERENCES raid_group(id) ON DELETE SET NULL,
    raid TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    date TEXT NOT NULL,
    start INTEGER NOT NULL,
    starts_at INTEGER NOT NULL,
    duration INTEGER NOT NULL DEFAULT 180,
    note TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open',
    created INTEGER NOT NULL
  );
  CREATE INDEX event_starts ON event(starts_at);
  CREATE TABLE signup (
    event_id TEXT NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    character_id TEXT NOT NULL REFERENCES character(id) ON DELETE CASCADE,
    user_id TEXT REFERENCES user(id) ON DELETE SET NULL,
    status TEXT NOT NULL,
    role TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    picked INTEGER NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'site',
    updated INTEGER NOT NULL,
    PRIMARY KEY (event_id, character_id)
  );
  CREATE TABLE boss (
    id TEXT PRIMARY KEY,
    raid TEXT NOT NULL,
    name TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    weights TEXT NOT NULL DEFAULT '{}',
    notes TEXT NOT NULL DEFAULT '',
    confidence TEXT NOT NULL DEFAULT 'C'
  );
  CREATE TABLE post (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    slug TEXT NOT NULL,
    title TEXT NOT NULL,
    excerpt TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT '',
    tags TEXT NOT NULL DEFAULT '[]',
    author_id TEXT REFERENCES user(id) ON DELETE SET NULL,
    published INTEGER,
    created INTEGER NOT NULL,
    updated INTEGER NOT NULL,
    UNIQUE (kind, slug)
  );
  CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE addon_action (
    user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    at INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
  );
  `,
  `ALTER TABLE character ADD COLUMN scanned_at INTEGER;
   ALTER TABLE character ADD COLUMN client TEXT;
   ALTER TABLE addon_action ADD COLUMN error TEXT;`,
  `UPDATE setting SET value = json_set(value, '$.name', 'Fratelli di Azeroth') WHERE key = 'guild' AND json_valid(value);`,
  `CREATE TABLE addon_connection (user_id TEXT PRIMARY KEY REFERENCES user(id) ON DELETE CASCADE, received INTEGER NOT NULL, detail TEXT NOT NULL);`,
]
