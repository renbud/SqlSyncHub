
/* =============================================
-- Author:		Renato
-- Create date: 
-- Description:	Return fully quoted object name for use in scripts

e.g.
SELECT McControl.[fnQuoteObjectName]('CRMSANDBOX.ProjectOneMigration.[dbo].[fnQuoteObjectName]',0);
SELECT McControl.[fnQuoteObjectName]('CRMSANDBOX.ProjectOneMigration.[dbo].[fnQuoteObjectName]',1);
-- ============================================= */
CREATE FUNCTION [SqlSync].[fnQuoteObjectName] (@ObjectName sysname, @StripServerName BIT=0)
RETURNS sysname
WITH EXECUTE AS CALLER
AS
BEGIN
	DECLARE @ServerName sysname, @DatabaseName sysname, @SchemaName sysname, @TableName sysname;
	SELECT @ServerName = PARSENAME(@ObjectName, 4);
	SELECT @DatabaseName = PARSENAME(@ObjectName, 3);
	SELECT @SchemaName = PARSENAME(@ObjectName, 2);
	SELECT @TableName = PARSENAME(@ObjectName, 1);

	RETURN CASE WHEN @StripServerName=0 THEN ISNULL(QUOTENAME(@ServerName) + '.','') ELSE '' END
		 + ISNULL(QUOTENAME(@DatabaseName) + '.', '')
		 + ISNULL(QUOTENAME(@SchemaName) + '.', '')
		 + QUOTENAME(@TableName);
END
