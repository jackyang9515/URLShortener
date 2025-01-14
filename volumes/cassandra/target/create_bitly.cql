use urlshortner;
CREATE TABLE IF NOT EXISTS bitly (
    shorturl text PRIMARY KEY,
    longurl text
);
