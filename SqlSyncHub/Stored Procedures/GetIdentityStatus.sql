
/******************************************************************************
Return a set of column names for @ObjectName
Return values: none

Dependencies:
Uses SQL Server 2012 features - works on SQLServer 2012+
may be better to use COLUMNPROPERTY(OBJECT_ID(C.TABLE_SCHEMA+'.'+C.TABLE_NAME),C.COLUMN_NAME,'IsIdentity') AS IDN

@ObjectName:  A table (or view) may be a 4 part name
@HasIdentity:  True if the table has an identity column
*******************************************************************************
**		Change History
*******************************************************************************
Date:			Author:			Description:
--------		--------		-------------------------------------------
18/04/2016      Renato          Created

Example:
DECLARE @HasIdentity bit
EXEC SqlSyncInternal.GetIdentityStatus 'AdventureWorks2012.Sales.SalesOrderHeader', @HasIdentity OUTPUT
SELECT @HasIdentity -- 1
*******************************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[GetIdentityStatus](@ObjectName sysname, @HasIdentity bit output)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ServerName sysname, @DatabaseName sysname, @SchemaName sysname, @TableName sysname;
	SELECT @ServerName = PARSENAME(@ObjectName, 4);
	SELECT @DatabaseName = PARSENAME(@ObjectName, 3);
	SELECT @SchemaName = PARSENAME(@ObjectName, 2);
	SELECT @TableName = PARSENAME(@ObjectName, 1);

	IF @ServerName >''
	  BEGIN
		THROW 51000, 'Cannot call GetIdentityStatus on remote server', 1
	  END

	DECLARE @SYSIDENT_TABLE sysname, @SYSOBJECTS_TABLE sysname;
	SET @SYSIDENT_TABLE = ISNULL(QUOTENAME(@ServerName)+'.', '')
						+ ISNULL(QUOTENAME(@DatabaseName)+'.', '')
						+ 'SYS.IDENTITY_COLUMNS';

	DECLARE @SQL nvarchar(4000);
	SELECT @HasIdentity=0

	IF (@DatabaseName IS NOT NULL)
		SET @SQL = N'USE '+QUOTENAME(@DatabaseName)+';'+CHAR(10);
	ELSE
		SET @SQL = N'';

	SET @SQL = @SQL + N'SELECT @HasIdentity=1' + CHAR(10) +
						N'FROM ' + @SYSIDENT_TABLE + ' AS IC' + CHAR(10) +
						N'WHERE IC.object_id= object_id(''' + @ObjectName + N''')' + CHAR(10);
  
	--PRINT @SQL;
	EXEC sp_executesql @SQL ,N'@HasIdentity BIT OUTPUT', @HasIdentity OUTPUT 
END
