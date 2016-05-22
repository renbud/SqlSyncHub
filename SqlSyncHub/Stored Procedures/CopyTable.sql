/******************************************************************************
Copies rows from @SourceTable to @TargetTable

Return values:
none

Parameters
-----------
@SourceTable sysname,	-- source table may be on remove server using 4 part name
@TargetTable sysname,	-- target table on current database server using up to 3 part name
@ExcludeColumns varchar(1000)=null	-- comma separated list of cols to exclude from copy


Dependencies
------------
Uses these SQLServer 2012+ features:
. PARSENAME
. EXECUTE(...) AT
. OFFSET x FETCH NEXT x ROWS ONLY

Uses these supporting objects:
SqlSync.CopyTableControl	- read/write
SqlSync.CopyTableLog		- write
SqlSync.GetColumnList		- exec
SqlSync.usp_RethrowError	- exec
SqlSync.fnQuoteObjectName()


Operation Modes
---------------

This function operates in one of three "modes", using @Mode
The @Mode to use is determined by looking at control data in SqlSync.CopyTableControl
	and also checking the existence of a single column primary key and the existence of a row version (timestamp) column
	on the source and target.

@Mode = INCREMENTAL
	Only download changed data
	The code tests these conditions and uses INCREMENTAL if:
		. Single column primary key exists at source
		. RowVersion (timestamp) column exists at source and target
		. SqlSync.CopyTableControl table has UseIncrementalCopy=true
		. SqlSync.CopyTableControl table has non-null value for LastCopyMaxRowVersion
	The following assumtions are untested if the above tests are all true. We assume the target will be set up like this
		. The name of single primary key column at source is also the name of the single primary key at the target
		. The name row version column at source is the name of a binary(8) column at target

@Mode = BATCH
	Truncate table, then download *ALL* data but do it in batches
	Possible if:
		a) Single column primary key exists at source

@Mode = SIMPLE
	Truncate table, then download *ALL* data in a single statement.

*******************************************************************************
**		Change History
*******************************************************************************
Date:			Author:			Description:
--------		--------		-------------------------------------------
18/05/2015      Renato          Created
21/05/2015      Renato          Refactor @Mode
15/04/2016      Renato          Change the way INCREMENTAL handles rowversion (dont require local rowversion)
								Incremental merge uses OPENQUERY instead of 4 part name (This has a limit of 8K query size)

Example:
EXEC SqlSync.CopyTable @SourceTable = 'TESTLINKEDSERVER.MyCompanyDatabase.dbo.AccessLog',
						@TargetTable  = 'MyCompanyDatabase.dbo.AccessLog'

EXEC SqlSync.CopyTable @SourceTable = 'TESTLINKEDSERVER.MyCompanyDatabase.dbo.AdminUser',
						@TargetTable  = 'MyCompanyDatabase.dbo.AdminUser'

EXEC SqlSync.CopyTable @SourceTable = 'TESTLINKEDSERVER.MyCompanyDatabase.dbo.CreditReturn',
						@TargetTable  = 'MyCompanyDatabase.dbo.CreditReturn'
*******************************************************************************/
CREATE PROCEDURE [SqlSync].[CopyTable] (
	@SourceTable sysname,				-- source table may be on remove server using 4 part name
	@TargetTable sysname,				-- target table on current database server using up to 3 part name
	@ExcludeColumns nvarchar(1000)=NULL,	-- comma separated list of cols to exclude from copy
	@DoDeleteIncremental BIT=0			-- Only delete records for incremental update if @DoDeleteIncremental=1
)
AS

BEGIN
	SET NOCOUNT ON;

	DECLARE	
			@RowsAffected INT,				-- Used to record @@rowcount
			@SQLString nvarchar(max),		-- Used for various dynamic SQL statements
			@ColList0 nvarchar(max),		-- All copied columns (plain comma separated column names)
			@ColList1 nvarchar(max),		-- All copied columns (expression converting some types to varchar(max) where remoting cannot deal with the type (e.g. xml)
			@ColListInsert nvarchar(max),	-- All copied columns (comma separated SOURCE.columnName,...)
			@ColListUpdate nvarchar(max),	-- All copied columns (comma separated columnName = SOURCE.columnName,...)
			@SourcePKCol sysname,			-- Primary key column (if single column on both source and target)
			@RowVersionCol sysname,			-- Row version (timestamp) column (if exists on source - not required on target)
			@Mode VARCHAR(15),				-- Mode of operation
			@UseIncrementalCopy BIT =1,		-- Default to use UseIncrementalCopy (only of LastMaxRowVersion exists)
			@LastMaxRowVersion BINARY(8),	-- Maximum row version recorded last sync
			@NewMaxRowVersion BINARY(8);	-- New source maximum row version (obtained from @@DBTS just prior to start of sync)

	PRINT 'updating ' + @TargetTable;
	PRINT '';

	DECLARE @SourceServerName sysname, @SourceDatabaseName sysname, @SourceSchemaName sysname, @SourceTableName sysname;
	DECLARE @TargetServerName sysname, @TargetDatabaseName sysname, @TargetSchemaName sysname, @TargetTableName sysname;
	SELECT @SourceServerName = PARSENAME(@SourceTable, 4);
	SELECT @SourceDatabaseName = PARSENAME(@SourceTable, 3);
	SELECT @SourceSchemaName = PARSENAME(@SourceTable, 2);
	SELECT @SourceTableName = PARSENAME(@SourceTable, 1);
	SELECT @TargetServerName = PARSENAME(@TargetTable, 4);
	SELECT @TargetDatabaseName = PARSENAME(@TargetTable, 3);
	SELECT @TargetSchemaName = PARSENAME(@TargetTable, 2);
	SELECT @TargetTableName = PARSENAME(@TargetTable, 1);

	DECLARE @InvalidTypeForRemoting TABLE (typename sysname);
	INSERT INTO @InvalidTypeForRemoting(typename) VALUES ('xml'),('geography'),('hierarchyid'),('geometry');

		   
	BEGIN TRY
		IF @SourceTable IS NULL OR @TargetTable IS NULL
			RAISERROR(N'CopyTable called with NULL parameters', -- Message text.
			   16, -- Severity,
			   1 -- State
			   ); 

		IF (@TargetServerName IS NULL AND OBJECT_ID(@TargetTable) IS NULL)
			RAISERROR(N'Table %s does not exist', -- Message text.
				16, -- Severity,
				1, -- State
				@TargetTable
				);

		IF (@SourceServerName IS NULL AND OBJECT_ID(@SourceTable) IS NULL)
			RAISERROR(N'View or table %s does not exist', -- Message text.
				16, -- Severity,
				1, -- State
				@SourceTable
				); 

		-- Make the table names canonical with []
		SET @SourceTable = SqlSync.fnQuoteObjectName(@SourceTable, 0);
		SET @TargetTable = SqlSync.fnQuoteObjectName(@TargetTable, 0);

		/******************************************************************************
		Initialise CopyTableControl for @TargetTable (if required)
		******************************************************************************/
		IF NOT EXISTS (SELECT * FROM SqlSync.CopyTableControl WHERE TargetTable = @TargetTable)
		BEGIN
			INSERT INTO SqlSync.CopyTableControl (TargetTable, UseIncrementalCopy)
			VALUES	(@TargetTable, 1); 
		END
  
  
		/******************************************************************************
		Calculate lists of columns for copying
		Also calculate primary key columns and row version column if they exist
		******************************************************************************/
		DECLARE @SourceCols XML, @TargetCols XML;
		EXEC SqlSyncInternal.GetObjectMetadata @ObjectName=@SourceTable, @OUTXML=@SourceCols  OUTPUT
  		EXEC SqlSyncInternal.GetObjectMetadata @ObjectName=@TargetTable, @OUTXML=@TargetCols  OUTPUT

		IF (@SourceCols IS NULL)
			RAISERROR(N'Table %s does not exist on server %s',
				16, -- Severity,
				1, -- State
				@SourceTable, @SourceServerName
				);

		IF (@TargetCols IS NULL)
			RAISERROR(N'View or table %s does not exist on server %s',
				16, -- Severity,
				1, -- State
				@TargetTable, @TargetServerName
				); 

		SELECT
			@ColList0 =      ISNULL(@ColList0+',', '') + QUOTENAME(COLUMN_NAME) ,
			@ColList1 =      ISNULL(@ColList1+',', '') + Expr ,
			@ColListInsert = ISNULL(@ColListInsert+ ',', '') +  'SOURCE.' + QUOTENAME(COLUMN_NAME) ,
			@ColListUpdate = CASE WHEN IsPk=0 AND IsIdent=0 THEN
								ISNULL(@ColListUpdate+ ',', '') + QUOTENAME(COLUMN_NAME) + '=SOURCE.' + QUOTENAME(COLUMN_NAME)
								ELSE
								@ColListUpdate+''
								END
		FROM
		(      
			SELECT Src.COLUMN_NAME, Src.Expr, Src.IsPK, Targ.IsIdent
			FROM
			(
				SELECT	col.value('(COL/.)[1]', 'sysname') AS COLUMN_NAME,
						CASE
							WHEN col.value('(TYP/.)[1]', 'sysname') IN (SELECT typename FROM @InvalidTypeForRemoting)
								THEN 'CONVERT(NVARCHAR(MAX),'+ QUOTENAME(col.value('(COL/.)[1]', 'sysname')) +') AS '+QUOTENAME(col.value('(COL/.)[1]', 'sysname'))
								ELSE QUOTENAME(col.value('(COL/.)[1]', 'sysname'))
							END AS Expr,
						col.value('(PK/.)[1]', 'bit') AS IsPK
				FROM	@SourceCols.nodes('/C') tbl ( col )
			) Src
			JOIN
			(
  				SELECT	col.value('(COL/.)[1]', 'sysname') AS COLUMN_NAME,
						col.value('(IDN/.)[1]', 'bit') AS IsIdent
				FROM	@TargetCols.nodes('/C') tbl ( col )
				WHERE	col.value('(COM/.)[1]', 'bit') != 1 -- Exclude computed
			) Targ
				ON Targ.COLUMN_NAME = Src.COLUMN_NAME
		) X
		WHERE (@ExcludeColumns IS NULL OR (','+@ExcludeColumns+',' NOT LIKE '%,' + X.COLUMN_NAME + ',%'));

		;WITH PKCols AS (      
			SELECT	col.value('(COL/.)[1]', 'sysname') AS COLUMN_NAME
			FROM	@SourceCols.nodes('/C') tbl (col)
			WHERE	col.value('(PK/.)[1]', 'bit') = 1
		)
		SELECT @SourcePKCol = COLUMN_NAME
		FROM PKCols C1
		GROUP BY COLUMN_NAME
		HAVING COUNT(*)=1  -- must be single column PK
			AND NOT EXISTS ( -- and no part of key can be a type that is incompatible with remoting
				SELECT 1
				FROM @SourceCols.nodes('/C') tbl (col)
				WHERE col.value('(COL/.)[1]', 'sysname') = COLUMN_NAME
					AND col.value('(TYP/.)[1]', 'sysname') IN (SELECT typename FROM @InvalidTypeForRemoting)
				);

		SELECT TOP 1 @RowVersionCol = COLUMN_NAME
		FROM
		(      
			SELECT	col.value('(COL/.)[1]', 'sysname') AS COLUMN_NAME
			FROM	@SourceCols.nodes('/C') tbl (col)
			WHERE	col.value('(TYP/.)[1]', 'sysname') = 'timestamp'
		) X;

		-- Get @NewMaxRowVersion
		EXEC SqlSyncInternal.GetDatabaseMaxRowVersion @SourceServerName, @SourceDatabaseName, @NewMaxRowVersion OUTPUT;
        
		/*
		-- Debug
		PRINT @Collist0;
		PRINT @ColList1;
		PRINT @ColListUpdate;
		PRINT @ColListInsert;
		PRINT @RowVersionCol;
		PRINT @SourcePKCol;
		PRINT @NewMaxRowVersion;
		*/

  		/******************************************************************************
		Determine @Mode
		******************************************************************************/
		IF (@SourcePKCol IS NOT NULL -- Single column primary key exists at source
			AND
			@RowVersionCol IS NOT NULL) -- RowVersion (timestamp) column exists at source (not required at target)
		BEGIN
			SELECT @UseIncrementalCopy=UseIncrementalCopy, @LastMaxRowVersion=LastCopyMaxRowVersion
			FROM SqlSync.CopyTableControl
			WHERE TargetTable = @TargetTable;

			IF (@UseIncrementalCopy=1 AND @LastMaxRowVersion IS NOT NULL)
				SELECT @Mode = 'INCREMENTAL'; -- Only download changed data
		END

		IF (@Mode IS NULL AND @SourcePKCol IS NOT NULL) -- Single column primary key exists at source
		BEGIN
			SELECT @Mode = 'BATCH'; -- Truncate table, then download *ALL* data but do it in batches
		END

		IF @Mode IS NULL
		BEGIN
			SELECT @Mode = 'SIMPLE'; -- Truncate table, then download *ALL* data in a single statement.
		END
		PRINT @Mode;    

		/******************************************************************************
		Handle the different modes
		******************************************************************************/
		IF @MODE = 'INCREMENTAL'
		BEGIN
			EXEC SqlSyncInternal.CopyTableIncremental
				@SourceServerName = @SourceServerName,
				@SourceTable = @SourceTable,
				@TargetTable = @TargetTable,
				@ColList0 = @ColList0,
				@ColList1 = @ColList1,
				@ColListInsert = @ColListInsert,
				@ColListUpdate = @ColListUpdate,
				@SourcePKCol = @SourcePKCol,	
				@RowVersionCol = @RowVersionCol,
				@LastMaxRowVersion = @LastMaxRowVersion,
				@DoDeleteIncremental = @DoDeleteIncremental
		END
  
  		IF @MODE = 'BATCH'
		BEGIN
			EXEC SqlSyncInternal.CopyTableBatch
				@SourceServerName = @SourceServerName,
				@SourceTable = @SourceTable,
				@TargetTable = @TargetTable,
				@ColList0 = @ColList0,
				@ColList1 = @ColList1,
				@ColListInsert = @ColListInsert,
				@SourcePKCol = @SourcePKCol
		END
  
    	IF @MODE = 'SIMPLE'
		BEGIN
			EXEC SqlSyncInternal.CopyTableSimple
				@SourceServerName = @SourceServerName,
				@SourceTable = @SourceTable,
				@TargetTable = @TargetTable,
				@ColList0 = @ColList0,
				@ColList1 = @ColList1,
				@ColListInsert = @ColListInsert
		END      
        


  		/******************************************************************************
		Update SqlSync.CopyTableControl
		******************************************************************************/
		UPDATE SqlSync.CopyTableControl
		SET LastCopyDateTime = GETDATE(),
			LastCopySourceTable = @SourceTable,
			LastCopyMaxRowVersion = @NewMaxRowVersion,
			IsOK =1,
			Message = NULL
		WHERE TargetTable = @TargetTable;

		RETURN 0;
	END TRY

	BEGIN CATCH
		IF (XACT_STATE()) IN (-1,1) 
			ROLLBACK TRAN;
		
		SET IDENTITY_INSERT SqlSync.CopyTableLog OFF;
		INSERT INTO SqlSync.CopyTableLog (SourceTable, TargetTable, OperationCode, [Message])
		VALUES	( @SourceTable, @TargetTable, 'Error', ERROR_MESSAGE()+ISNULL(CHAR(10)+@SQLString,''));

		UPDATE SqlSync.CopyTableControl
		SET LastCopyDateTime = GETDATE(),
			LastCopySourceTable = @SourceTable,
			IsOK =0,
			MESSAGE = ERROR_MESSAGE()
					+ISNULL(CHAR(10)+@SQLString,'')
					+ISNULL(CHAR(10)+ISNULL(ERROR_PROCEDURE(), '-')+' line:'+CONVERT(VARCHAR(10),ERROR_LINE()),'')
		WHERE TargetTable = @TargetTable;

		--THROW;
	    EXEC SqlSyncInternal.usp_RethrowError;
	    RETURN 1;
	END CATCH
END
