CREATE TABLE IF NOT EXISTS hazel.accounts (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_name VARCHAR(96) NOT NULL,
    balance DECIMAL(14,2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    KEY accounts_updated_at_idx (updated_at)
) ENGINE=InnoDB;

INSERT INTO hazel.accounts (account_name, balance)
VALUES ('warren', 1000), ('hazel', 1250), ('fiver', 900), ('bigwig', 1500);

CREATE TABLE IF NOT EXISTS hazel.events (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_id BIGINT NOT NULL,
    event_kind VARCHAR(32) NOT NULL,
    payload JSON,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    KEY events_account_created_idx (account_id, created_at)
) ENGINE=InnoDB;

REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'hazel'@'%';
GRANT SELECT ON hazel.* TO 'hazel'@'%';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'hazel'@'%';
GRANT SELECT ON performance_schema.* TO 'hazel'@'%';
GRANT SELECT ON sys.* TO 'hazel'@'%';
FLUSH PRIVILEGES;
