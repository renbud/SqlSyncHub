/**************************************************************************************
Top line entry procedure to reconcile all tables in CopyTableControl
This captures the rowcounts from the source and target into the CopyTableControl table

The table counts are updated into CopyTableControl
The actual reporting on discrepancies needs to be done separately to this.
For example see the EmailAlert procedure for one way to report
 rowcount differences using a tolerance.
**************************************************************************************/
CREATE PROCEDURE [SqlSync].[ReconcileAllTables]
	@SourceServerIn sysname = null,
	@SourceDatabaseIn sysname = null,
	@TargetDatabaseIn sysname = null
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @TargetRowCounts TABLE(TableName sysname, SchemaName sysname, ROWS BIGINT);
	DECLARE @SourceRowCounts TABLE(TableName sysname, SchemaName sysname, ROWS BIGINT);
	DECLARE @TargetServer sysname, @TargetDatabase sysname, @SourceServer sysname, @SourceDatabase sysname;
	DECLARE @LastCountDateTime DATETIME2(0) = GETDATE();


	DECLARE dbcur CURSOR STATIC LOCAL FOR
	SELECT DISTINCT  TargetServer ,
		TargetDatabase ,
		SourceServer ,
		SourceDatabase 
	FROM SqlSync.vwCopyTableControl
		WHERE (SourceServer = @SourceServerIn OR @SourceServerIn IS NULL)
		AND (SourceDatabase = @SourceDatabaseIn OR @SourceDatabaseIn IS NULL)
		AND (TargetDatabase = @TargetDatabaseIn OR @TargetDatabaseIn IS NULL);

	OPEN dbcur
	WHILE 1=1
	BEGIN
		FETCH NEXT FROM dbcur INTO @TargetServer, @TargetDatabase, @SourceServer, @SourceDatabase;
		IF @@FETCH_STATUS<>0 BREAK;

		SET @LastCountDateTime = GETDATE();

		DECLARE @UseSourceDatabase sysname = ISNULL('USE ' + QUOTENAME(@SourceDatabase)+'; ', '');
		IF @SourceServer IS NOT NULL 
		BEGIN
  			INSERT INTO @SourceRowCounts
					(TableName, SchemaName, ROWS)
			EXEC (' EXEC (''' + @UseSourceDatabase + '
				SELECT object_name(I.id) as TableName, OBJECT_SCHEMA_NAME(I.id) as SchemaName, I.rows
				FROM sys.sysindexes I
				WHERE I.indid IN (0,1)
				'') AT ' + @SourceServer );
		END
		ELSE
		BEGIN
    		INSERT INTO @SourceRowCounts
				(TableName, SchemaName, ROWS)
			EXEC (@UseSourceDatabase + '
				SELECT object_name(I.id) as TableName, OBJECT_SCHEMA_NAME(I.id) as SchemaName, I.rows
				FROM sys.sysindexes I
				WHERE I.indid IN (0,1)
				' );
		END
  
  		DECLARE @UseTargetDatabase sysname = ISNULL('USE ' + QUOTENAME(@TargetDatabase)+'; ', '');
		IF @TargetServer IS NOT NULL 
		BEGIN
  			INSERT INTO @TargetRowCounts
					(TableName, SchemaName, ROWS)
			EXEC (' EXEC (''' + @UseTargetDatabase + '
				SELECT object_name(I.id) as TableName, OBJECT_SCHEMA_NAME(I.id) as SchemaName, I.rows
				FROM sys.sysindexes I
				WHERE I.indid IN (0,1)
				'') AT ' + @TargetServer );
		END
		ELSE
		BEGIN
    		INSERT INTO @TargetRowCounts
				(TableName, SchemaName, ROWS)
			EXEC (@UseTargetDatabase + '
				SELECT object_name(I.id) as TableName, OBJECT_SCHEMA_NAME(I.id) as SchemaName, I.rows
				FROM sys.sysindexes I
				WHERE I.indid IN (0,1)
				' );
		END
 
		UPDATE C 
		SET CountTrg = TR.ROWS, CountSrc = SR.ROWS, LastCountDateTime = @LastCountDateTime
		FROM SqlSync.vwCopyTableControl C
		JOIN @TargetRowCounts TR
			ON TR.SchemaName = C.TargetSchema
				AND TR.TableName = C.TargetTable
		JOIN @SourceRowCounts SR
			ON SR.SchemaName = C.SourceSchema
				AND SR.TableName = C.SourceTable
		WHERE ISNULL(C.TargetServer,'') = ISNULL(@TargetServer,'')
			 AND ISNULL(C.TargetDatabase,'') = ISNULL(@TargetDatabase,'');
	END
END
