/******************************************************************************
Copies @SourceTable from Azure CRM to Azure database
Return values: none

Dependencies:
Uses SQL Server 2012 features - works on SQLServer 2012+

This procedure has the source linked server hard-coded
It also "knows" the naming conventions for the source and target schemas

*******************************************************************************
**		Change History
*******************************************************************************
Date:				Author:			Description:
--------			--------		-------------------------------------------
5th Feb 2016		Renato          Created

Example:
EXEC SqlServerSyncDemo.CopyAzureTable 'Person.Person'
EXEC SqlServerSyncDemo.CopyAzureTable 'Person.PersonPhone'
*******************************************************************************/
CREATE PROCEDURE [SqlSyncDemo].[CopyAzureTable]
(
	@SourceTable sysname,
	@ExcludeColumns nvarchar(1000)=null	-- comma separated list of cols to exclude from copy
)
AS
BEGIN
	DECLARE @SourceTableFull sysname,
			@TargetTableFull sysname;

	DECLARE @SourcePrefix sysname = 'NMWSW4VV8N_MvcMovieRen_db.MvcMovieRen_db.';

	SELECT @SourceTableFull = @SourcePrefix + @SourceTable;
	PRINT @SourceTableFull


	SELECT @TargetTableFull =  @SourceTable;
	PRINT @TargetTableFull

	EXEC SqlSync.CopyTable @SourceTableFull, @TargetTableFull, @ExcludeColumns
END
