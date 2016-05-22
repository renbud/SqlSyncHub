CREATE TABLE [SqlSync].[ForeignKeyScript] (
    [DatabaseName] [sysname]      NOT NULL,
    [DropScript]   NVARCHAR (MAX) NULL,
    [CreateScript] NVARCHAR (MAX) NULL,
    CONSTRAINT [PK_ForeignKeyScript] PRIMARY KEY CLUSTERED ([DatabaseName] ASC)
);

