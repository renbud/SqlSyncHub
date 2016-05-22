

/******************************************************************************
Return the current latest database timestamp/rowversion @@DBIT
from ServerName.DatabaseName

@ServerName:	The name of a linked server (to SqlServer) or NULL for the local server
@DatabaseName:  The name of the database to get @@DBIT (mandatory even if its current database)
*******************************************************************************
**		Change History
*******************************************************************************
Date:			Author:			Description:
--------		--------		-------------------------------------------
15/04/2016      Renato          Created

Example:
DECLARE @DBTS binary(8)
EXEC SqlSync.GetDatabaseMaxRowVersion 'TESTLINKEDSERVER', 'MyCompanyDatabase', @DBTS OUTPUT
SELECT @DBTS

DECLARE @DBTS binary(8)
EXEC SqlSync.GetDatabaseMaxRowVersion NULL, 'MyCompanyDatabase', @DBTS OUTPUT
SELECT @DBTS
*******************************************************************************/
CREATE PROCEDURE [SqlSyncInternal].[GetDatabaseMaxRowVersion](@ServerName sysname, @DatabaseName sysname, @DBTS BINARY(80) output)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @SqlMaxVer NVARCHAR(1000);
	IF ISNULL(@ServerName,'') > ''
	BEGIN
		DECLARE @MAXROWVERSION BINARY(8);
		SET @SqlMaxVer = ISNULL(N'USE ' + QUOTENAME(@DatabaseName)+'; ',N'') + N' SELECT @@DBTS';
		DECLARE @SqlExec NVARCHAR(1000) = N'
			DECLARE @TempRowVer TABLE (MaxRowVersion BINARY(8));
			INSERT INTO @TempRowVer(MaxRowVersion)
			EXEC (''' + 
				@SqlMaxVer + '''
			) AT ' + QUOTENAME(@ServerName) + N'
			SELECT TOP 1 @MaxRowVersion = MaxRowVersion FROM @TempRowVer;'
		EXEC sp_executesql @SqlExec, N'@MaxRowVersion BINARY(8) OUTPUT', @DBTS OUTPUT;
	END
	ELSE
	BEGIN
		SET @SqlMaxVer = ISNULL(N'USE ' + @DatabaseName+'; ',N'') + N' SELECT @MaxRowVersion=@@DBTS';  
		EXEC sp_executesql @sqlMaxVer, N'@MaxRowVersion BINARY(8) OUTPUT', @DBTS OUTPUT;
	END
 
END

