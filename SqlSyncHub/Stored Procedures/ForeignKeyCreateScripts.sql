
/***********************************************
Create DROP scripts and CREATE script for all FKs in the database
Place these scripts in the SqlSync.ForeignKeyScript table

** Only run this procedure when foreign keys exist on the database

http://social.technet.microsoft.com/wiki/contents/articles/2958.script-to-create-all-foreign-keys.aspx

e.g:
EXEC SqlSync.ForeignKeyCreateScripts 'MyCompanyDatabase'

-- Drop Constraints
DECLARE @DropScript nvarchar(max);
SELECT TOP 1 @DropScript = DropScript FROM SqlSync.ForeignKeyScript WHERE DatabaseName='MyCompanyDatabase';
EXEC sp_executesql @DropScript;

-- Re-Create Constraints
DECLARE @CreateScript nvarchar(max);
SELECT TOP 1 @CreateScript = CreateScript FROM SqlSync.ForeignKeyScript WHERE DatabaseName='MyCompanyDatabase';
EXEC sp_executesql @CreateScript;

************************************************/
CREATE PROCEDURE [SqlSync].[ForeignKeyCreateScripts]
	@TargetDatabase sysname
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @sDrop nvarchar(4000), @screate nvarchar(4000);
	DECLARE @Drop   nvarchar(max) = ISNULL(N'USE ' + @TargetDatabase + ';'+ char(10), N''),
			@Create nvarchar(max) = ISNULL(N'USE ' + @TargetDatabase + ';'+ char(10), N'');

	-- drop is easy, just build a simple concatenated list from sys.foreign_keys:
	SELECT @sDrop = 
	ISNULL(N'USE ' + QUOTENAME(@TargetDatabase) + ';'+ char(10), N'') + N'
	SELECT @drop += 
	''IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE NAME=''''''+fk.NAME+'''''') ALTER TABLE '' + QUOTENAME(cs.name) + ''.'' + QUOTENAME(ct.name) 
		+ '' DROP CONSTRAINT '' + QUOTENAME(fk.name) + '';''+ char(10)
	FROM sys.foreign_keys AS fk
	INNER JOIN sys.tables AS ct
	  ON fk.parent_object_id = ct.[object_id]
	INNER JOIN sys.schemas AS cs 
	  ON ct.[schema_id] = cs.[schema_id];
	  ';

	-- SELECT @sdrop;
	EXEC sp_executesql @sDrop, N'@TargetDatabase sysname, @drop nvarchar(max) output', @TargetDatabase, @Drop OUTPUT
  
	-- create is a little more complex. We need to generate the list of 
	-- columns on both sides of the constraint, even though in most cases
	-- there is only one column.
	SELECT @sCreate =
	ISNULL(N'USE ' + QUOTENAME(@TargetDatabase) + ';'+ char(10), N'') + N'
	SELECT @create +=
	N''IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE NAME=''''''+fk.NAME+'''''') ALTER TABLE '' 
	   + QUOTENAME(cs.name) + ''.'' + QUOTENAME(ct.name)
	   + CASE WHEN fk.is_not_trusted=1 THEN '' WITH NOCHECK'' ELSE '''' END 
	   + '' ADD CONSTRAINT '' + QUOTENAME(fk.name) 
	   + '' FOREIGN KEY ('' + STUFF((SELECT '','' + QUOTENAME(c.name)
	   -- get all the columns in the constraint table
		FROM sys.columns AS c 
		INNER JOIN sys.foreign_key_columns AS fkc 
		ON fkc.parent_column_id = c.column_id
		AND fkc.parent_object_id = c.[object_id]
		WHERE fkc.constraint_object_id = fk.[object_id]
		ORDER BY fkc.constraint_column_id 
		FOR XML PATH(N''''), TYPE).value(N''.[1]'', N''nvarchar(max)''), 1, 1, N'''')
	  + '') REFERENCES '' + QUOTENAME(rs.name) + ''.'' + QUOTENAME(rt.name)
	  + ''('' + STUFF((SELECT '','' + QUOTENAME(c.name)
	   -- get all the referenced columns
		FROM sys.columns AS c 
		INNER JOIN sys.foreign_key_columns AS fkc 
		ON fkc.referenced_column_id = c.column_id
		AND fkc.referenced_object_id = c.[object_id]
		WHERE fkc.constraint_object_id = fk.[object_id]
		ORDER BY fkc.constraint_column_id 
		FOR XML PATH(N''''), TYPE).value(N''.[1]'', N''nvarchar(max)''), 1, 1, N'''') + '')'' + CASE WHEN fk.is_not_for_replication=1 THEN ''NOT FOR REPLICATION'' ELSE '''' END + '';''+ char(10)
	FROM sys.foreign_keys AS fk
	INNER JOIN sys.tables AS rt -- referenced table
	  ON fk.referenced_object_id = rt.[object_id]
	INNER JOIN sys.schemas AS rs 
	  ON rt.[schema_id] = rs.[schema_id]
	INNER JOIN sys.tables AS ct -- constraint table
	  ON fk.parent_object_id = ct.[object_id]
	INNER JOIN sys.schemas AS cs 
	  ON ct.[schema_id] = cs.[schema_id]
	WHERE rt.is_ms_shipped = 0 AND ct.is_ms_shipped = 0;
	'
	-- SELECT @screate;
	EXEC sp_executesql @sCreate, N'@TargetDatabase sysname, @create nvarchar(max) output', @TargetDatabase, @Create OUTPUT
  
	IF (@Create LIKE '%ALTER TABLE%')
	BEGIN
		DELETE FROM SqlSync.ForeignKeyScript WHERE DatabaseName = @TargetDatabase;
		INSERT SqlSync.ForeignKeyScript(DatabaseName, DropScript, CreateScript)
		SELECT @TargetDatabase, @Drop, @Create;

		PRINT 'Scripts updated';
	END
	ELSE
	BEGIN  
	  RAISERROR(N'There are no foreign keys to script. The SqlSync.ForeignKeyScript has not been updated', -- Message text.
			   16, -- Severity,
			   1 -- State
			   );   
	END  
	SELECT * FROM SqlSync.ForeignKeyScript;
END
