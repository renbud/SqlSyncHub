# SqlSyncHub
SQL Server synchronization framework.

Keywords (replication , synchronisation, SQL Server)

This repository contains a small database with stored procedures that supports simple replication between SQL Servers.
The database is installed on the target server.
There is no software required on the source server apart from SQL Server.

Synopsis
========

To copy a table's data from a source to a target table:

```
EXEC SqlSync.CopyTable
     @SourceTable = @SourceTable2or3or4PartName, @TargetTable = @TargetTable2Or3PartName
```

To check that the row counts from all source and target tables match:
```
EXEC SqlSync.ReconcileAllTables
```

Behaviour
=========
When tables are copied, columns are matched by name. Non-matching columns are ignored. Implicit data type conversion occurs only between compatible types.
Source tables with a single column primary key and a row-version columns are copies incrementally after an initial full copy.
Source tables with a single column primary key are copied in batch mode.
Source tables without a single column primary key (or whose primary key column is not supported natively by remoting) are copied in a simple unbatched mode.
This mode may result in excessive use of resources such as log disk space and timeouts.