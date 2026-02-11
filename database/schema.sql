-- Auth
-------
CREATE TABLE IF NOT EXISTS "User" (
    id INTEGER PRIMARY KEY NOT NULL,
    username TEXT NOT NULL UNIQUE,

    CHECK (username <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS "Token" (
    id INTEGER PRIMARY KEY NOT NULL,
    user_id INTEGER NOT NULL UNIQUE,
    value TEXT NOT NULL,

    FOREIGN KEY(user_id) REFERENCES User(id)
) STRICT;

CREATE TABLE IF NOT EXISTS "Secret" (
    id INTEGER PRIMARY KEY NOT NULL,
    salt TEXT NOT NULL,
    hashed_password TEXT NOT NULL,

    FOREIGN KEY(id) REFERENCES User(id)
) STRICT;

-- Cards
--------
CREATE TABLE IF NOT EXISTS "Set_" (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    release_date TEXT NOT NULL,

    CHECK (name <> ''),
    CHECK (release_date <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS "Card" (
    id INTEGER PRIMARY KEY NOT NULL UNIQUE,
    tcgdex_id TEXT NOT NULL,
    set_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    image_url TEXT,
    cardmarket_id INTEGER,

    CHECK (tcgdex_id <> ''),
    CHECK (name <> ''),

    FOREIGN KEY(set_id) REFERENCES Set_(id)
) STRICT;

CREATE TABLE IF NOT EXISTS "Variant" (
    id INTEGER PRIMARY KEY NOT NULL,
    card_id INTEGER NOT NULL,
    type TEXT NOT NULL,
    subtype TEXT,
    size TEXT,
    stamps BLOB NOT NULL,
    foil TEXT,

    CHECK (type <> ''),
    CHECK (subtype IS NULL OR subtype <> ''),
    CHECK (size IS NULL OR size <> ''),
    CHECK (foil IS NULL OR foil <> ''),

    FOREIGN KEY(card_id) REFERENCES Card(id),

    CONSTRAINT different UNIQUE (card_id, type, subtype, size, stamps, foil)
) STRICT;

CREATE TABLE IF NOT EXISTS "Owned" (
    id INTEGER PRIMARY KEY NOT NULL,
    user_id INTEGER NOT NULL,
    variant_id INTEGER NOT NULL,
    owned INTEGER NOT NULL,

    CHECK (owned == 0 OR owned == 1),

    FOREIGN KEY(user_id) REFERENCES user(id),
    FOREIGN KEY(variant_id) REFERENCES variant(id)
) STRICT;
