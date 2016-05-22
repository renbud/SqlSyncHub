/****************************************************************
Sample top line entry procedure to copy all tables

e.g:

EXEC SqlSyncDemo.SynchroniseAllTables
	@SourcePrefix = 'TESTLINKEDSERVER.AdventureWorks2012.',
	@TargetDatabase = 'AdventureWorks2012Copy'
*****************************************************************/
CREATE PROCEDURE [SqlSyncDemo].[SynchroniseAllTables]
	@SourcePrefix sysname,	-- [<servername>.]<databasename>.
	@TargetDatabase sysname ,
	@OnlyRetryErrors BIT = 0,
	@DoDeleteIncremental BIT=0	
AS
BEGIN 
	DECLARE @OnlyStatusFailed BIT = ISNULL(@OnlyRetryErrors,0);

	DECLARE @SourceTable sysname;
	DECLARE @TargetTable sysname;


	EXEC SqlSync.ForeignKeyCreateScripts @TargetDatabase;

	-- Drop Constraints
	DECLARE @DropScript nvarchar(max);
	SELECT TOP 1 @DropScript = DropScript FROM SqlSync.ForeignKeyScript WHERE DatabaseName= @TargetDatabase;
	EXEC sp_executesql @DropScript;


	;DECLARE cc CURSOR STATIC LOCAL FOR
	WITH TBL AS (
		SELECT
			SqlSync.fnQuoteObjectName(@SourcePrefix+TABLE_SCHEMA+'.'+TABLE_NAME,0) AS SourceTable, 
			SqlSync.fnQuoteObjectName(@TargetDatabase+'.'+TABLE_SCHEMA+'.'+TABLE_NAME,0) AS TargetTable
		FROM AdventureWorks2012Copy.INFORMATION_SCHEMA.TABLES
		WHERE
			TABLE_TYPE='BASE TABLE'
			AND TABLE_NAME NOT IN ('sysdiagrams')
	)
	SELECT TBL.SourceTable, TBL.TargetTable
	FROM TBL
	WHERE 
		(
			@OnlyStatusFailed = 0
			OR
			EXISTS (SELECT * FROM SqlSync.CopyTableControl WHERE ISNULL(IsOK,0)=0 AND TargetTable=TBL.TargetTable)
		);

	OPEN cc;
	WHILE 1=1
	BEGIN
		FETCH NEXT FROM cc INTO @SourceTable, @TargetTable;
		IF @@FETCH_STATUS<>0 BREAK;

		EXECUTE SqlSync.CopyTable
		   @SourceTable = @SourceTable
		  ,@TargetTable = @TargetTable
		  ,@ExcludeColumns = '',
		  @DoDeleteIncremental = @DoDeleteIncremental;
	END
END
