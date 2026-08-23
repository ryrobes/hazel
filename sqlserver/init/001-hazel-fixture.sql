IF DB_ID(N'hazel') IS NULL
BEGIN
    CREATE DATABASE hazel;
END;
GO

IF SUSER_ID(N'hazel') IS NULL
BEGIN
    CREATE LOGIN hazel WITH PASSWORD = 'Hazel-dev-only!42', CHECK_POLICY = OFF;
END;
GO

GRANT VIEW SERVER PERFORMANCE STATE TO hazel;
GO

USE hazel;
GO

IF USER_ID(N'hazel') IS NULL
BEGIN
    CREATE USER hazel FOR LOGIN hazel;
END;
GO

ALTER ROLE db_datareader ADD MEMBER hazel;
GRANT VIEW DATABASE PERFORMANCE STATE TO hazel;
GO

IF OBJECT_ID(N'dbo.accounts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.accounts
    (
        id int NOT NULL CONSTRAINT PK_accounts PRIMARY KEY,
        owner_name nvarchar(100) NOT NULL,
        balance decimal(18, 2) NOT NULL,
        updated_at datetime2(3) NOT NULL CONSTRAINT DF_accounts_updated_at DEFAULT SYSUTCDATETIME()
    );

    INSERT dbo.accounts (id, owner_name, balance)
    VALUES
        (1, N'Ada', 1000.00),
        (2, N'Grace', 2000.00),
        (3, N'Linus', 3000.00),
        (4, N'Margaret', 4000.00);
END;
GO
