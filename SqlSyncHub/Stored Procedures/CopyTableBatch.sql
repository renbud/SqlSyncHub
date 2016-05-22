/**********************************************************************
EXEC SqlSyncInternal.CopyTableBatch
			@SourceServerName = 'TESTLINKEDSERVER',
			@SourceTable ='TESTLINKEDSERVER.MyCompanyDatabase.dbo.AdminUser',
			@TargetTable='MyCompanyDb.dbo.AdminUser',
			@ColList0='[Id],[FirstName],[LastName],[Telephone],[Email],[NetworkId],[EmployeeId],[LastSync],[IsActive],[Created],[CreditApprovalMaxAmount],[PeopleSoftId],[IsAriseActive]',
			@ColList1='[Id],[FirstName],[LastName],[Telephone],[Email],[NetworkId],[EmployeeId],[LastSync],[IsActive],[Created],[CreditApprovalMaxAmount],[PeopleSoftId],[IsAriseActive]',
			@ColListInsert ='SOURCE.[Id],SOURCE.[FirstName],SOURCE.[LastName],SOURCE.[Telephone],SOURCE.[Email],SOURCE.[NetworkId],SOURCE.[EmployeeId],SOURCE.[LastSync],SOURCE.[IsActive],SOURCE.[Created],SOURCE.[CreditApprovalMaxAmount],SOURCE.[PeopleSoftId],SOURCE.[IsAriseActive]',
			@SourcePKCol='Id'
**********************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[CopyTableBatch] (
			@SourceServerName sysname,		-- Server hosting source table
			@SourceTable sysname,			-- Up to 4 part name
			@TargetTable sysname,			-- Up to 3 part name
			@ColList0 nvarchar(max),			-- All copied columns (plain comma separated column names)
			@ColList1 nvarchar(max),			-- All copied columns (expression converting some types to varchar(max) where remoting cannot deal with the type (e.g. xml)
			@ColListInsert nvarchar(max),	-- All copied columns (comma separated SOURCE.columnName,...)
			@SourcePKCol sysname			-- Primary key column (if single column on both source and target)
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
		+ char(10) + N'WHERE (? IS NULL OR [' + @SourcePKCol + '] > ? )' 
		+ char(10) + N'ORDER BY [' + @SourcePKCol + ']'
		+ char(10) + ' OFFSET 0 ROWS FETCH NEXT ? ROWS ONLY;'', @MaxKeyValue, @MaxKeyValue, @BATCH_SIZE) AT ' + QUOTENAME(@SourceServerName)
	END
	ELSE
	BEGIN
  		SET @SQLString = @SQLString
		+ char(10) + N'WHERE (@MaxKeyValue IS NULL OR [' + @SourcePKCol + '] > @MaxKeyValue )' 
		+ char(10) + N'ORDER BY [' + @SourcePKCol + ']'
		+ char(10) + N' OFFSET 0 ROWS FETCH NEXT @BATCH_SIZE ROWS ONLY;'
	END
 
	SET @SQLString = @SQLString + char(10) + N'SET @RowsAffected = @@ROWCOUNT;'

	EXEC SqlSyncInternal.AllowIdentityInsert @TargetTable, @SQLString OUTPUT;

	PRINT @SQLString

	/*****************
	Insert
	******************/
	PRINT 'Start copy...';
	BEGIN TRY
		/******************************************************************************
		Control loop for batched insert statement
		******************************************************************************/
		-- Execute Insert statement
		DECLARE
  					@RowsAffected INT,		-- Used to record @@rowcount  
					@RowsSoFar INT=0,		-- We can only handle max (int) ~2 billion rows
					@BATCH_SIZE INT=200000,
					@MaxKeyValue SQL_VARIANT;
		SET @RowsAffected = @BATCH_SIZE;
		WHILE @RowsAffected = @BATCH_SIZE
		BEGIN
			EXEC sp_executesql
				@SQLString,
				N'@BATCH_SIZE INT, @MaxKeyValue SQL_VARIANT, @RowsAffected INT OUTPUT',
				@BATCH_SIZE, @MaxKeyValue, @RowsAffected OUTPUT

			CHECKPOINT;
			SET @RowsSoFar = @RowsSoFar + @RowsAffected;

			PRINT 'Rows affected='+CONVERT(VARCHAR(10),@RowsAffected)+'...';
			--PRINT 'K:'+CONVERT(VARCHAR(100),ISNULL(@MaxKeyValue,'NULL'));

			INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, RowsAffected )
			VALUES	( @SourceTable, @TargetTable, 'Insert', @RowsAffected);

			/******************************************************************************
			Find @MaxKeyValue
			******************************************************************************/
			DECLARE @SqlString2 NVARCHAR(MAX);
			BEGIN      
				SET @SqlString2 = N'SELECT @MaxKeyValue = MAX(' + @SourcePKCol + ')'
					+ CHAR(10) + 'FROM ' + SqlSync.fnQuoteObjectName(@TargetTable, 0);

				EXEC sp_executesql @SqlString2, N'@MaxKeyValue SQL_VARIANT OUTPUT', @MaxKeyValue OUTPUT;
			END
		END
  		/******************************************************************************
		End control loop for batched insert statement
		******************************************************************************/
	END TRY
	BEGIN CATCH
		EXEC SqlSyncInternal.usp_RethrowError @SQLString;
	END CATCH
	PRINT 'Finished copy...';
END

