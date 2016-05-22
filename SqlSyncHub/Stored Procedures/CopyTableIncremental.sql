/**********************************************************************
EXEC SqlSyncInternal.CopyTableIncremental
			@SourceServerName = 'TESTLINKEDSERVER',								-- Server hosting source table
			@SourceTable ='TESTLINKEDSERVER.MyCompanyDatabase.dbo.EmailLog',	-- Up to 4 part name
			@TargetTable='MyCompanyDatabase.dbo.EmailLog',						-- Up to 3 part name
			@ColList0='[Id],[EmailTemplateId],[RegistrationId],[SenderAddress],[RecipientAddress],[Sent],[RegistrationWorkflowId],[JMailLogId],[CreditReturnWorkflowId],[DealRegistrationId]',			-- All copied columns (plain comma separated column names)
			@ColList1='[Id],[EmailTemplateId],[RegistrationId],[SenderAddress],[RecipientAddress],[Sent],[RegistrationWorkflowId],[JMailLogId],[CreditReturnWorkflowId],[DealRegistrationId]',			-- All copied columns (expression converting some types to varchar(max) where remoting cannot deal with the type (e.g. xml)
			@ColListInsert ='SOURCE.[Id],SOURCE.[EmailTemplateId],SOURCE.[RegistrationId],SOURCE.[SenderAddress],SOURCE.[RecipientAddress],SOURCE.[Sent],SOURCE.[RegistrationWorkflowId],SOURCE.[JMailLogId],SOURCE.[CreditReturnWorkflowId],SOURCE.[DealRegistrationId]',	-- All copied columns (comma separated SOURCE.columnName,...)
			@ColListUpdate='[EmailTemplateId]=SOURCE.[EmailTemplateId],[RegistrationId]=SOURCE.[RegistrationId],[SenderAddress]=SOURCE.[SenderAddress],[RecipientAddress]=SOURCE.[RecipientAddress],[Sent]=SOURCE.[Sent],[RegistrationWorkflowId]=SOURCE.[RegistrationWorkflowId],[JMailLogId]=SOURCE.[JMailLogId],[CreditReturnWorkflowId]=SOURCE.[CreditReturnWorkflowId],[DealRegistrationId]=SOURCE.[DealRegistrationId]',	-- All copied columns (comma separated columnName = SOURCE.columnName,...)
			@SourcePKCol='Id',						-- Primary key column (if single column on both source and target)
			@RowVersionCol='RowVersionCol',			-- Row version (timestamp) column (if exists on source - not required on target)
			@LastMaxRowVersion=0x00000000005E1757,
			@DoDeleteIncremental=1
**********************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[CopyTableIncremental] (
			@SourceServerName sysname,		-- Server hosting source table
			@SourceTable sysname,			-- Up to 3 part name
			@TargetTable sysname,			-- Up to 4 part name
			@ColList0 nvarchar(max),		-- All copied columns (plain comma separated column names)
			@ColList1 nvarchar(max),		-- All copied columns (expression converting some types to varchar(max) where remoting cannot deal with the type (e.g. xml)
			@ColListInsert nvarchar(max),	-- All copied columns (comma separated SOURCE.columnName,...)
			@ColListUpdate nvarchar(max),	-- All copied columns (comma separated columnName = SOURCE.columnName,...)
			@SourcePKCol sysname,			-- Primary key column (if single column on both source and target)
			@RowVersionCol sysname,			-- Row version (timestamp) column (if exists on source - not required on target)
			@LastMaxRowVersion BINARY(8),	-- Maximum row version recorded last sync
			@DoDeleteIncremental BIT = 0	-- Delete rows that are not on the source (requires copy of *all* source PKs!)
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @SQLString NVARCHAR(MAX),
			@MergeSrc NVARCHAR(MAX),
			@RowsAffected INT;

	/******************************************************************************
	Handle deleted records (If option @DoDeleteIncremental=1)
	This is quite inefficient because it copies every primary key from the source
	into SqlSync.TempEntityPrimaryKey and then does DELETE WHERE NOT IN
	******************************************************************************/
  	IF @DoDeleteIncremental=1
	BEGIN        
		DECLARE @TempEntityPrimaryKey sysname;
		SET @TempEntityPrimaryKey =  'tempdb.dbo.' +ISNULL(PARSENAME(@SourceTable, 2),'dbo') + '_' + PARSENAME(@SourceTable, 1);

		-- Create the temp keys table
		SET @SQLString = 'BEGIN TRY ' + CHAR(10) +
				'CREATE TABLE '+SqlSync.fnQuoteObjectName(@TempEntityPrimaryKey,1)+
				'(' + QUOTENAME(@SourcePKCol) +' SQL_VARIANT NOT NULL PRIMARY KEY)' + CHAR(10) +
				'; END TRY'+ CHAR(10) +'BEGIN CATCH'+CHAR(10)+'END CATCH';
		--PRINT @SQLString
		EXEC sp_executesql @SQLString , N'';

		-- Populate the temp keys table
		DECLARE @ColListInsertPK NVARCHAR(1000)= 'SOURCE.' + @SourcePKCol;

		EXEC [SqlSyncInternal].[CopyTableBatch]
			@SourceServerName  = @SourceServerName,		-- Server hosting source table
			@SourceTable  = @SourceTable,				-- Up to 4 part name
			@TargetTable = @TempEntityPrimaryKey,		-- Up to 3 part name
			@ColList0  = @SourcePKCol,					-- All copied columns (plain comma separated column names)
			@ColList1 = @SourcePKCol,					-- All copied columns (expression converting some types to varchar(max) where remoting cannot deal with the type (e.g. xml)
			@ColListInsert = @ColListInsertPK,			-- All copied columns (comma separated SOURCE.columnName,...)
			@SourcePKCol = @SourcePKCol	

		-- Delete local records where key not in the temp keys table
		SET @SQLString = N'DELETE FROM '+ SqlSync.fnQuoteObjectName(@TargetTable, 0) +
						' WHERE '+QUOTENAME(@SourcePKCol)+' NOT IN (SELECT '+QUOTENAME(@SourcePKCol)+
						' FROM '+SqlSync.fnQuoteObjectName(@TempEntityPrimaryKey,1)+ ');';
		SET @SQLString = @SQLString + char(10) + N'SET @RowsAffected = @@ROWCOUNT;'
		--PRINT @SQLString
		EXEC sp_executesql @SQLString , N'@RowsAffected INT OUTPUT', @RowsAffected OUTPUT;

		INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, RowsAffected )
		VALUES	( @SourceTable, @TargetTable, 'Del Incr', @RowsAffected);

		-- Drop the temp keys table
		SET @SQLString = 'BEGIN TRY ' + CHAR(10) +
						' DROP TABLE '+SqlSync.fnQuoteObjectName(@TempEntityPrimaryKey,1)+';' + CHAR(10) +
						' END TRY' + CHAR(10) + 'BEGIN CATCH'+CHAR(10)+'END CATCH';
		EXEC sp_executesql @SQLString , N'';
	END
   
	/**********************************************
	Handle new and updated records
	***********************************************/
	-- Prefer OPENQUERY
	SELECT @MergeSrc = 'SELECT ' + @ColList0
			+ CHAR(10) + N' FROM OPENQUERY(' + @SourceServerName + ', ''SELECT ' + @ColList1 + ' FROM '  + SqlSync.fnQuoteObjectName(@SourceTable, 1)
			+ CHAR(10) + N' WHERE ' + @RowVersionCol + ' > %LastMaxRowVersion% %TopMaxRowVersion% '')';

	-- USE 4 part name
	IF (LEN(@MergeSrc)>8000 OR @SourceServerName IS NULL)
	BEGIN
		SELECT @MergeSrc = 'SELECT ' + @ColList0
				+ CHAR(10) + N' FROM ' + SqlSync.fnQuoteObjectName(@SourceTable, 0)
				+ CHAR(10) + N'WHERE ' + @RowVersionCol + ' > %LastMaxRowVersion% %TopMaxRowVersion% ';
	END
					      
	SET @SQLString =N'MERGE ' + SqlSync.fnQuoteObjectName(@TargetTable, 0) + ' AS TARGET '
			+ CHAR(10) + ' USING (' + @MergeSrc + ') AS SOURCE '
			+ CHAR(10) + ' ON (TARGET.[' + @SourcePKCol + '] = SOURCE.[' + @SourcePKCol + ']) '
			+ CHAR(10) + ' WHEN MATCHED THEN UPDATE SET '+ @ColListUpdate
			+ CHAR(10) + ' WHEN NOT MATCHED BY TARGET THEN INSERT ('+ @ColList0 + ') VALUES ('+ @ColListInsert + ');';
			--Merge will not work  on remote server when referencing source as another remote

	SET @SQLString = @SQLString + char(10) + N'SET @RowsAffected = @@ROWCOUNT;'

	EXEC SqlSyncInternal.AllowIdentityInsert @TargetTable, @SQLString OUTPUT;

	PRINT @SQLString
	PRINT 'Start copy...';
	BEGIN TRY
		/******************************************************************************
		Control loop for batched insert statement
		******************************************************************************/
		-- Execute Insert statement
		DECLARE		@RowsSoFar INT=0,		-- We can only handle max (int) ~2 billion rows
					@BATCH_SIZE INT=10000;

		WHILE 1=1 
		BEGIN

			DECLARE @TopMaxRowVersion BINARY(8);	-- Maximum version to prevent the batch being too large
			DECLARE @SQLTopRow NVARCHAR(MAX);
			SET @SQLTopRow = N'
			SELECT @TopMaxRowVersion = TopMaxRowVersion FROM OPENQUERY(' + @SourceServerName + ', ''
			SELECT TOP 1 LEAD(' + @RowVersionCol + ','+CONVERT(VARCHAR(10),@BATCH_SIZE-1)+') OVER(ORDER BY ' + @RowVersionCol + ') AS TopMaxRowVersion
			FROM '  + SqlSync.fnQuoteObjectName(@SourceTable, 1)
			+ CHAR(10) + N'	WHERE ' + @RowVersionCol + ' > ' + sys.fn_varbintohexstr(@LastMaxRowVersion) + ''');';

			EXEC sp_executesql @SQLTopRow, N'@TopMaxRowVersion BINARY(8) OUTPUT', @TopMaxRowVersion OUTPUT

			-- xxxx
			PRINT 'LastMaxRowVersion=' + sys.fn_varbintohexstr(@LastMaxRowVersion);
			PRINT 'TopMaxRowVersion=' + sys.fn_varbintohexstr(@TopMaxRowVersion);

			DECLARE @SQLStringMain NVARCHAR(MAX);
			SET @SQLStringMain = REPLACE(@SqlString,'%LastMaxRowVersion%',sys.fn_varbintohexstr(@LastMaxRowVersion));
			SET @SQLStringMain = REPLACE(@SQLStringMain,'%TopMaxRowVersion%',
				ISNULL('AND ' + @RowVersionCol + ' <= ' + sys.fn_varbintohexstr(@TopMaxRowVersion), ''));

		
			PRINT @SQLStringMain
			EXEC sp_executesql @SQLStringMain, N'@RowsAffected INT OUTPUT', @RowsAffected OUTPUT;

			CHECKPOINT;

			PRINT 'Rows affected='+CONVERT(VARCHAR(10),@RowsAffected)+'...';
			SET @RowsSoFar = @RowsSoFar + @RowsAffected;

			INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, RowsAffected )
			VALUES	( @SourceTable, @TargetTable, 'Merge', @RowsAffected);

			IF @TopMaxRowVersion IS NOT NULL
			BEGIN      
				UPDATE SqlSync.CopyTableControl
				SET LastCopyMaxRowVersion = @TopMaxRowVersion
				WHERE TargetTable = @TargetTable
			END

			SET @LastMaxRowVersion = @TopMaxRowVersion;
			SET @TopMaxRowVersion = NULL;

			IF (ISNULL(@RowsAffected,0) = 0) BREAK;
			IF @LastMaxRowVersion IS NULL BREAK;
		END
  	END TRY
	BEGIN CATCH
		EXEC SqlSyncInternal.usp_RethrowError @SQLStringMain;
	END CATCH  
  	PRINT 'Finished copy';
END
