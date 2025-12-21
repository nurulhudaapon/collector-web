CREATE TABLE IF NOT EXISTS user (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,

    CHECK (name <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS card (
    id TEXT PRIMARY KEY NOT NULL UNIQUE,
    name TEXT NOT NULL,
    image_url TEXT,

    CHECK (id <> ''),
    CHECK (name <> ''),
    CHECK (image_url IS NULL OR image_url <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS variant (
    id INTEGER PRIMARY KEY NOT NULL,
    card_id TEXT NOT NULL,
    type TEXT NOT NULL,
    subtype TEXT,
    size TEXT,
    stamp TEXT,
    foil TEXT,

    FOREIGN KEY(card_id) REFERENCES card(id),

    CHECK (type <> ''),
    CHECK (subtype IS NULL OR subtype <> ''),
    CHECK (size IS NULL OR size <> ''),
    CHECK (stamp IS NULL OR stamp <> ''),
    CHECK (foil IS NULL OR foil <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS owned (
    user_id INTEGER NOT NULL,
    variant_id INTEGER NOT NULL,
    owned INTEGER NOT NULL,

    FOREIGN KEY(user_id) REFERENCES user(id),
    FOREIGN KEY(variant_id) REFERENCES variant(id),

    CHECK (owned == 0 OR owned == 1)
) STRICT;
