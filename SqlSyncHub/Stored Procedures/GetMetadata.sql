/******************************************************************************
Return a set of table and column properties for @ServerName.@DatabaseName

Dependencies:
Uses SQL Server 2012 features - works on SQLServer 2012+

@ServerName:	Input linked server pointing a to SQL Server database (or NULL)
@DatabaseName:	Input database
@MetaData:		Output XML representation of the metadata
*******************************************************************************
**		Change History
*******************************************************************************
Date:			Author:			Description:
--------		--------		-------------------------------------------
17/04/2016      Renato          Created

Example:
DECLARE @L XML
EXEC SqlSync.GetMetadata NULL, 'AdventureWorks', @L OUTPUT
SELECT @L
SELECT
			MD.cols.query('SCH').value('.', 'varchar(255)'),
			MD.cols.query('TAB').value('.', 'varchar(255)'),
			MD.cols.query('COL').value('.', 'varchar(255)')
		FROM @L.nodes('/C') MD(cols);

DECLARE @L XML
EXEC SqlSync.GetMetadata  'TESTLINKEDSERVER', 'MyCompanyDatabase', @L OUTPUT, @Force=1
SELECT
			MD.cols.query('SCH').value('.', 'varchar(255)'),
			MD.cols.query('TAB').value('.', 'varchar(255)'),
			MD.cols.query('COL').value('.', 'varchar(255)')
		FROM @L.nodes('/C') MD(cols);
*******************************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[GetMetadata]
	@ServerName sysname, @DatabaseName sysname, @MetaData XML OUTPUT, @Force BIT=0
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ServerNameOrBlank sysname;
	DECLARE @HoursToLiveInCache smallint = 4;

	SET @ServerNameOrBlank = ISNULL(@ServerName,'');
	IF @DatabaseName IS NULL SET @DatabaseName = DB_NAME();

	SELECT @MetaData = MetaData
	FROM SqlSync.MetaData
	WHERE
		ServerName = @ServerNameOrBlank
		AND DatabaseName = @DatabaseName
		AND DateUpdated > DATEADD(HOUR, -HoursToLiveInCache, GETDATE());

	IF @MetaData IS NULL OR @Force=1
	BEGIN
		DECLARE @MetaDataTbl TABLE(MetaData xml);
		INSERT INTO @MetaDataTbl(MetaData)
		EXEC SqlSyncInternal.RunViewOnDatabase 'SqlSyncInternal.vwMetaDataQuery', @ServerName, @DatabaseName;

		SELECT TOP 1 @MetaData = MetaData
		FROM @MetaDataTbl;

		UPDATE SqlSync.MetaData
		SET MetaData = @MetaData,
			DateUpdated = GETDATE()
		WHERE
			ServerName = @ServerNameOrBlank
			AND DatabaseName = @DatabaseName;

		IF (@@ROWCOUNT = 0)
		BEGIN
			INSERT INTO SqlSync.MetaData
					   (ServerName
					   ,DatabaseName
					   ,DateUpdated
					   ,HoursToLiveInCache
					   ,MetaData)
				 VALUES
					   (@ServerNameOrBlank
					   ,@DatabaseName
					   ,GETDATE()
					   ,@HoursToLiveInCache
					   ,@MetaData);
		END
	END
END
