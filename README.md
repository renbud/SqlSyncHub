# SqlSyncHub
SQL Server synchronization framework 
Keywords (replication , synchronisation, SQL Server)

This repository contains a database project that supports simple SQL server replication.
The database is installed on the target server. There is no software required on the source server apart from SQL Server.
The database contains about 30 procedures functions and views as well as a few tables which are logs and cached metadata.

The main entry points are:

/* Copy table copies from source to target, matching columns by name. Non-matching columns are ignored */
EXEC SqlSync.CopyTable
     @SourceTable = @SourceTable2or3or4PartName, @TargetTable = @TargetTable2Or3PartName


and


