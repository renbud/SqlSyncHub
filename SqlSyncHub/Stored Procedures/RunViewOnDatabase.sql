/***********************************************************************************
Returns the result of SELECT * FROM @ViewName executed on 

@ViewName:		1 or 2 part Name of a view defined on the local database
@ServerName:	A linked server pointing a to SQL Server database (or NULL)
@DatabaseName:	A database

e.g
DECLARE @Tbl TABLE(col1 xml);
INSERT INTO @Tbl
EXEC SqlSyncInternal.RunViewOnDatabase 'SqlSyncInternal.vwMetaDataQuery', NULL, 'AdventureWorks2012';
SELECT
	MD.cols.query('SCH').value('.', 'varchar(255)'),
	MD.cols.query('TAB').value('.', 'varchar(255)'),
	MD.cols.query('COL').value('.', 'varchar(255)')
FROM @Tbl
CROSS APPLY col1.nodes('/C') MD(cols)

DECLARE @Tbl TABLE(col1 xml);
INSERT INTO @Tbl
EXEC SqlSyncInternal.RunViewOnDatabase 'SqlSyncInternal.vwMetaDataQuery', 'TESTLINKEDSERVER', 'MyCompanyDatabase'
SELECT
	MD.cols.query('SCH').value('.', 'varchar(255)'),
	MD.cols.query('TAB').value('.', 'varchar(255)'),
	MD.cols.query('COL').value('.', 'varchar(255)')
FROM @Tbl
CROSS APPLY col1.nodes('/C') MD(cols)
***********************************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[RunViewOnDatabase](@ViewName sysname, @ServerName sysname = NULL, @DatabaseName sysname = NULL)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Sql nvarchar(4000), @pos int;

	SELECT TOP 1 @Sql = RTRIM(LTRIM(text))
	FROM syscomments C
	WHERE C.id = object_id(@ViewName)
	ORDER BY c.colid;

	DECLARE @keyword NVARCHAR(50) = N'%--RunViewOnDatabase%';
	SELECT @pos = PATINDEX(@keyword, @sql);
	IF (@pos > 0)
	BEGIN
		-- Trim everything before and including the keyword comment - leaving just the SELECT
		SELECT @sql = stuff(@sql, 1, @pos+LEN(@keyword)-1,'');
	END
	ELSE
	BEGIN 
		-- Did not find keyword. Try to remove CREATE VIEW .. leaving just the SELECT
		-- but this is dodgy.
		SELECT @Sql = replace(@Sql,'CREATE VIEW ' + @ViewName+ ' AS','');
	END
	--PRINT @sql;
	SELECT @Sql = isnull('USE ' + QUOTENAME(@DatabaseName) + ';' + char(10), '') +@Sql;
	--PRINT @sql;

	IF @ServerName is NULL
	BEGIN
		EXEC sp_executesql @Sql;
	END
	ELSE
	BEGIN
		DECLARE @OuterSql nvarchar(4000);
		SELECT @OuterSql = 'EXEC ( ' + SqlSyncInternal.fnQuoteSqlText(@Sql) + ') AT ' + Quotename(@ServerName);

		--PRINT @OuterSql;
		EXEC sp_executesql @OuterSql;
	END
END
