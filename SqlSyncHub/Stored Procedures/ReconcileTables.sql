/**************************************************************************************
Demo Top line entry procedure to reconcile tables for AdventureWorks2012
This captures the rowcounts from the source and target into the CopyTableControl table

This demonstrates one way to reconcile table counts for a target database
**************************************************************************************/
CREATE PROCEDURE SqlSyncDemo.ReconcileTables
AS
BEGIN
	EXEC SqlSync.ReconcileAllTables @TargetDatabaseIn = 'AdventureWorks2012Copy';
END
