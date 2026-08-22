CREATE DATABASE IF NOT EXISTS hazel;

CREATE TABLE IF NOT EXISTS hazel.events
(
    event_time DateTime64(3),
    account_id UInt64,
    event_kind LowCardinality(String),
    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_kind, account_id, event_time);

INSERT INTO hazel.events
SELECT
    now64(3) - toIntervalSecond(number % 86400),
    number % 10000,
    multiIf(number % 7 = 0, 'write', number % 5 = 0, 'read', 'tick'),
    repeat('x', 48)
FROM numbers(250000);

CREATE USER IF NOT EXISTS hazel IDENTIFIED WITH plaintext_password BY 'hazel-dev-only';
GRANT SELECT ON hazel.* TO hazel;
GRANT SELECT ON system.* TO hazel;
