-- Auth
-------
CREATE TABLE IF NOT EXISTS "User" (
    id INTEGER PRIMARY KEY NOT NULL,
    username TEXT NOT NULL UNIQUE,

    CHECK (username <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS "Token" (
    id INTEGER PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,

    FOREIGN KEY(id) REFERENCES User(id)
) STRICT;

CREATE TABLE IF NOT EXISTS "Secret" (
    id INTEGER PRIMARY KEY NOT NULL,
    salt TEXT NOT NULL,
    hashed_password TEXT NOT NULL,

    FOREIGN KEY(id) REFERENCES User(id)
) STRICT;

-- Cards
--------
CREATE TABLE IF NOT EXISTS "Card" (
    id INTEGER PRIMARY KEY NOT NULL,
    card_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    image_url TEXT,

    CHECK (card_id <> ''),
    CHECK (name <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS "Variant" (
    id INTEGER PRIMARY KEY NOT NULL,
    card_id TEXT NOT NULL,
    type TEXT NOT NULL,
    subtype TEXT,
    size TEXT,
    stamp TEXT,
    foil TEXT,

    FOREIGN KEY(card_id) REFERENCES card(card_id),

    CHECK (type <> ''),
    CHECK (subtype IS NULL OR subtype <> ''),
    CHECK (size IS NULL OR size <> ''),
    CHECK (stamp IS NULL OR stamp <> ''),
    CHECK (foil IS NULL OR foil <> '')
) STRICT;

CREATE TABLE IF NOT EXISTS "Owned" (
    user_id INTEGER NOT NULL,
    variant_id INTEGER NOT NULL,
    owned INTEGER NOT NULL,

    FOREIGN KEY(user_id) REFERENCES user(id),
    FOREIGN KEY(variant_id) REFERENCES variant(id),

    CHECK (owned == 0 OR owned == 1)
) STRICT;
