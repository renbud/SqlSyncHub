CREATE TABLE [SqlSync].[SchemaChangeDetectIgnore] (
    [DatabasePair] NVARCHAR (518) NULL,
    [SourceTable]  [sysname]      NULL,
    [SourceCol]    [sysname]      NULL,
    [TargetTable]  [sysname]      NULL,
    [TargetCol]    [sysname]      NULL
);

