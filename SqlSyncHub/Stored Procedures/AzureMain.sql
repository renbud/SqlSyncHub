
/***************************************
Mainline procedure to drive repopulation of al data from Dynamics
This is intended to be scheduled to run nightly outside business hours
e.g:

EXEC SqlServerSyncDemo.AzureMain
***************************************/
CREATE PROC [SqlSyncDemo].[AzureMain]
AS
BEGIN
	-- Drop Constraints (see ForeignKeyCreateScripts)
	DECLARE @DropScript nvarchar(max);
	SELECT TOP 1 @DropScript = DropScript FROM SqlSync.ForeignKeyScript;
	EXEC sp_executesql @DropScript;

	EXEC SqlSyncDemo.CopyAzureTable 'Person.Person', NULL
	EXEC SqlSyncDemo.CopyAzureTable 'Person.Address', NULL
	EXEC SqlSyncDemo.CopyAzureTable 'Person.EmailAddress', NULL
	EXEC SqlSyncDemo.CopyAzureTable 'Person.PersonPhone', NULL

	-- Re-Create Constraints (see ForeignKeyCreateScripts)
	DECLARE @CreateScript nvarchar(max);
	SELECT TOP 1 @CreateScript = CreateScript FROM SqlSync.ForeignKeyScript;
	EXEC sp_executesql @CreateScript;
END


