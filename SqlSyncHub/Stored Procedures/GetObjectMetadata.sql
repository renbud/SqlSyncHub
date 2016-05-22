/******************************************************************************
Return a set of column names for @ObjectName
Return values: none

Dependencies:
Uses SQL Server 2012 features - works on SQLServer 2012+

@ObjectName:  A table (or view) may be a 4 part name
@OUTXML:  XML representation of column names
	<C><COL>colname</COL><TYP>coltype></TYP></C> ...
	e.g.
	<C><COL>ContactId</COL><TYP>uniqueidentifier</TYP></C> <C><COL>CustomerTypeCode</COL><TYP>char(1)</TYP></C>...

*******************************************************************************
**		Change History
*******************************************************************************
Date:			Author:			Description:
--------		--------		-------------------------------------------
09/03/2016      Renato          Created

Example:
DECLARE @L XML
EXEC SqlSyncInternal.GetObjectMetadata 'MyCompanyDatabase.dbo.CreditReturn', @L OUTPUT
SELECT	col.value('(COL/.)[1]', 'sysname') AS COLUMN_NAME,
						col.value('(IDN/.)[1]', 'bit') AS IsIdent
				FROM	@L.nodes('/C') tbl ( col )
				WHERE	col.value('(COM/.)[1]', 'bit') != 1 -- Exclude computed

DECLARE @L XML
EXEC SqlSyncInternal.GetObjectMetadata '[AdventureWorks2012].Person.Person', @L OUTPUT

DECLARE @L XML
EXEC SqlSyncInternal.GetObjectMetadata 'TESTLINKEDSERVER.MyCompanyDatabase.dbo.InvoiceData', @L OUTPUT
SELECT	col.value('(COL/.)[1]', 'sysname') AS COLUMN_NAME,
		col.value('(TYP/.)[1]', 'sysname') AS DATA_TYPE,
		CASE WHEN col.value('(TYP/.)[1]', 'sysname') IN ('xml','geography','hierarchyid','geometry') THEN 'CONVERT(VARCHAR(MAX),'+ QUOTENAME(col.value('(COL/.)[1]', 'sysname')) +')' ELSE QUOTENAME(col.value('(COL/.)[1]', 'sysname')) END AS EXPR
FROM	@L.nodes('C') tbl ( col )
*******************************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[GetObjectMetadata]
	@ObjectName sysname, @OUTXML XML OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ServerName sysname, @DatabaseName sysname, @SchemaName sysname, @TableName sysname, @MetaData xml;;
	SELECT @ServerName = PARSENAME(@ObjectName, 4);
	SELECT @DatabaseName = PARSENAME(@ObjectName, 3);
	SELECT @SchemaName = PARSENAME(@ObjectName, 2);
	SELECT @TableName = PARSENAME(@ObjectName, 1);

	EXEC SqlSyncInternal.GetMetadata @ServerName, @DatabaseName, @MetaData OUTPUT;

	SELECT @OUTXML =
	(
		SELECT   MD.cols.query('.')
		FROM @MetaData.nodes('/C') MD(cols)
		WHERE MD.cols.query('SCH').value('.', 'varchar(255)') = @SchemaName
			AND MD.cols.query('TAB').value('.', 'varchar(255)') = @TableName
		FOR XML PATH('')
	);

END
