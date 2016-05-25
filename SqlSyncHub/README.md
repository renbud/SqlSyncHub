# SqlSyncHub
SQL Server synchronization framework.

Keywords (replication , synchronisation, SQL Server)

This repository contains a database project that supports simple replication between SQL Servers.
The database is installed on the target server. There is no software required on the source server apart from SQL Server. The SqlSyncHub database is quite small. It contains about 30 objects, mostly procedures, functions and views. There are a few tables containing logs and cached metadata.

Synopsis
========

To copy a table’s data from a source to a target table, call the procedure SqlSync.CopyTable as follows:

```
EXEC SqlSync.CopyTable
     @SourceTable = @SourceTable2or3or4PartName, @TargetTable = @TargetTable2Or3PartName
```

To check that the row counts from all source and target tables match:
```
EXEC SqlSync.ReconcileAllTables
```