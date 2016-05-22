CREATE TABLE [SqlSync].[CopyTableControl] (
    [TargetTable]           [sysname]     NOT NULL,
    [UseIncrementalCopy]    BIT           NOT NULL,
    [LastCopySourceTable]   [sysname]     NULL,
    [LastCopyDateTime]      DATETIME2 (0) NULL,
    [LastCopyMaxRowVersion] BINARY (8)    NULL,
    [IsOK]                  BIT           NULL,
    [Message]               VARCHAR (MAX) NULL,
    [CountSrc]              BIGINT        NULL,
    [CountTrg]              BIGINT        NULL,
    [LastCountDateTime]     DATETIME2 (0) NULL,
    CONSTRAINT [PK_CopyTableControl] PRIMARY KEY CLUSTERED ([TargetTable] ASC)
);

