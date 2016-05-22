CREATE TABLE [SqlSync].[CopyTableLog] (
    [CopyTableLogID] INT           IDENTITY (1, 1) NOT NULL,
    [LogDateTime]    DATETIME2 (0) CONSTRAINT [DF_CopyTableLog_LogDateTime] DEFAULT (getdate()) NOT NULL,
    [SourceTable]    [sysname]     NOT NULL,
    [TargetTable]    [sysname]     NOT NULL,
    [OperationCode]  VARCHAR (10)  NOT NULL,
    [RowsAffected]   INT           NULL,
    [Message]        VARCHAR (MAX) NULL,
    CONSTRAINT [PK_CopyTable_Log] PRIMARY KEY CLUSTERED ([CopyTableLogID] ASC)
);



