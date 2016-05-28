/**********************************************************************
EXEC SqlSyncInternal.CopyTableSimple
			@SourceServerName = 'TESTLINKEDSERVER',
			@SourceTable ='TESTLINKEDSERVER.MyCompanyDatabase.dbo.CreditStatus',
			@TargetTable='MyCompanyDatabase.dbo.CreditStatus',
			@ColList0='[EnumId],[Name],[DisplayName]',
			@ColList1='[EnumId],[Name],[DisplayName]',
			@ColListInsert ='[Name]=SOURCE.[Name],[DisplayName]=SOURCE.[DisplayName]'
**********************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[CopyTableSimple] (
			@SourceServerName sysname,		-- Server hosting source table
			@SourceTable sysname,			-- Up to 4 part name
			@TargetTable sysname,			-- Up to 3 part name
			@ColList0 nvarchar(max),			-- All copied columns (plain comma separated column names)
			@ColList1 nvarchar(max),			-- All copied columns (expression converting some types to varchar(max) where remoting cannot deal with the type (e.g. xml)
			@ColListInsert nvarchar(max)	-- All copied columns (comma separated SOURCE.columnName,...)
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @SQLString nvarchar(MAX);

	/***************************
	 Delete the existing data 
	***************************/
	BEGIN TRY
		-- Try to Truncate the table
		SET @SQLString = N'TRUNCATE TABLE ' +  SqlSync.fnQuoteObjectName(@TargetTable, 0) + ';'
		EXEC sp_executesql @SQLString , N'';

		INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, RowsAffected )
		VALUES	( @SourceTable, @TargetTable, 'Truncate', NULL);
	END TRY
	BEGIN CATCH
		-- Truncate failed, try delete          
  		SET @SQLString = N'DELETE FROM ' +  SqlSync.fnQuoteObjectName(@TargetTable, 0) + ';'
		EXEC sp_executesql @SQLString , N'';

		INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, RowsAffected )
		VALUES	( @SourceTable, @TargetTable, 'Delete', NULL);
	END CATCH
 
 	/***************************
	 Target table is now invalid
	***************************/
  	UPDATE SqlSync.CopyTableControl
	SET LastCopyDateTime = GETDATE(),
		LastCopySourceTable = @SourceTable,
		IsOK =0,
		Message = 'In Progress'
	WHERE TargetTable = @TargetTable;          

	/***************************
	Prepare to insert
	***************************/
	SET @SQLString = N'INSERT INTO ' + SqlSync.fnQuoteObjectName(@TargetTable, 0)
		+ char(10) + N' (' + @ColList0 + N')';

	IF @SourceServerName IS NOT NULL
	BEGIN
  		-- If the source is on a remote server then
		-- Execute OFFSET FETCH remotely at server USING EXEC(...) AT
		-- Because its inefficient to do this using 4 part name syntax   
		SET @SqlString = @SqlString + char(10) +  N'EXEC (''';
	END
  
	SET @SqlString = @SqlString
		+ char(10) + N' SELECT '
		+ char(10) + @ColList1
		+ char(10) + N' FROM ' + SqlSync.fnQuoteObjectName(@SourceTable, 1);

	IF @SourceServerName IS NOT NULL
	BEGIN
		-- Execute OFFSET FETCH remotely at server USING EXEC(...) AT     
		SET @SQLString = @SQLString
		+ char(10) + ''')  AT ' + QUOTENAME(@SourceServerName)
	END
 
	SET @SQLString = @SQLString + char(10) + N'SET @RowsAffected = @@ROWCOUNT;'

	EXEC SqlSyncInternal.AllowIdentityInsert @TargetTable, @SQLString OUTPUT;

	PRINT @SQLString

	/*****************
	Insert
	******************/
	BEGIN TRY
		-- Execute Insert statement
		DECLARE	@RowsAffected INT;

		EXEC sp_executesql @SQLString, N'@RowsAffected INT OUTPUT', @RowsAffected OUTPUT;

		CHECKPOINT;

		PRINT 'Rows affected='+CONVERT(VARCHAR(10),@RowsAffected)+'...';

		INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, RowsAffected )
		VALUES	( @SourceTable, @TargetTable, 'Insert', @RowsAffected);
	END TRY
	BEGIN CATCH
		DECLARE @Msg NVARCHAR(4000) = left(@SQLString);
		EXEC SqlSyncInternal.usp_RethrowError @Msg;
	END CATCH
END

