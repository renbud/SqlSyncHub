CREATE TABLE [SqlSync].[MetaData] (
    [ServerName]         [sysname]     NOT NULL,
    [DatabaseName]       [sysname]     NOT NULL,
    [DateUpdated]        DATETIME2 (0) NOT NULL,
    [HoursToLiveInCache] SMALLINT      CONSTRAINT [DF_MetaData_HoursToLiveInCache] DEFAULT ((8)) NOT NULL,
    [MetaData]           XML           NOT NULL,
    CONSTRAINT [PK_MetaData] PRIMARY KEY CLUSTERED ([ServerName] ASC, [DatabaseName] ASC)
);



