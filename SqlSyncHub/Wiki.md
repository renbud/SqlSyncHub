Overview
========
SQL Sync Hub is a framework for copying data from one SQL Server database to another.

It can be used as an alternative to replication in cases where the replication agents cannot be configured, or where a simple framework with open source code is preferred.

The framework is used by calling the _SqlSync.CopyTable_ procedure for each table to be synchronised or copied. This replaces all data in the target table by default, but if the source table contains a rowversion (timestamp) column then an incremental *upsert* is performed. In order to keep things simple, _CopyTable_ automatically copies columns wherever the source column name matches the target. There is no way to provide alternate column matching.

The framework is delivered in a SQL Server database that is installed on the target SQL Server. This database contains the _CopyTable_ procedure as well as supporting procedures, functions and views.

Synopsis
========

To copy a table’s data from a source to a target table, call the procedure _SqlSync.CopyTable_ as follows:

    EXEC SqlSync.CopyTable
         @SourceTable = @SourceTable2or3or4PartName, @TargetTable = @TargetTable2Or3PartName

# Architecture

##Why use SQL Sync Hub

Copying data from one table to another is a very common requirement, and there are many existing solutions. So why use SQL Sync Hub?

-   **Zero Footprint on Source**

Solutions such as replication and solutions based on change tracking or change data capture require log reading agent at the source to detect and track changes. These solutions require administrative changes and schema changes to the source server and database. If you cannot make such changes, then you need a solution that simply reads the data and schema from the source. SQL Sync Hub is such a solution. It does not require administrative or write access to the source database. (It can, however, greatly improve performance to create a timestamp column on large source tables so that an incremental copy is done).

-   **Automatic Column Matching**

SQL Sync Hub automatically copies columns wherever the source column name matches the target. The metadata is queried at run-time, so schema changes are detected with each run. Any non-matching columns are ignored. Implicit SQL Server conversion occurs if the datatypes of source and target differ. This differs from typical ETL tools such as SSIS or Informatica which require a developer to match columns and code any conversions.

*Warning*: SQL Sync Hub may not be suitable for copying large tables without a single column primary key. See Modes of Copy for details.

##Dependencies

Both the source and target servers must be Microsoft SQL Server 2012 or later versions.

The source server may be SQL Azure or any on premise edition of SQL Server.

The target server can be any on premise edition of SQL Server, but *cannot* be SQL Azure because Azure currently does not allow cross database access.

##Modes of Copy

SQL Sync Hub automatically copies columns wherever the source column name matches the target. The metadata is queried at run-time, so schema changes are detected with each run. Any non-matching columns are ignored.

The CopyTable procedure operates in one of 3 modes. The mode is chosen automatically based on the table schema.

**Incremental copy**: if a *rowversion* column exists on the source table and a single column primary key exists on both source and target tables, then *incremental* copy occurs. The latest timestamp on the source database prior to the last successful copy is stored in the CopyTableControl table. Source table rows with a timestamp greater than this are selected from the source and used in a MERGE statement. The operation is done in batches to prevent excessive log consumption on the source or target and to provide a unit of retry. The batches are controlled by the rowversion.
Incremental copy does not delete source rows by default. An optional parameter specifies that rows on the target will be deleted if they are not on the source. This is quite an expensive operation, which is why it is possible to schedule this separately. The entire set of source primary keys is copied to a temporary table using batch copy, and the temporary table drives a deletion using an anti-join.

**Batch copy**: if incremental copy cannot be used, but if a single
column primary key exists on both source and target tables, then *batch*
copy occurs. All data is first cleared from the source table by TRUNCATE
if possible, otherwise by DELETE. Rows are selected from source and
inserted into the target. The operation is done in batches to prevent
excessive log consumption on the source or target and to provide a unit
of retry. The batches are controlled by the primary key.

**Simple copy**: if neither incremental nor batch copy can be used, then
*simple* copy occurs. All data is first cleared from the source table by
TRUNCATE if possible, otherwise by DELETE. Rows are selected from source
and inserted into the target. The operation is done in a single unit.

*Warning*: SQL Sync Hub may not be suitable for copying large tables
without a single column primary key. If the framework is forced to do a
simple copy on a large table, then this could cause problems with
performance, log use and stability.

##Feature Summary

-   Uses a *Source* and *Target* paradigm.

-   Data is copied from a source table to a target table.

-   Data is pulled by the target server.

-   Typically, the target server accesses the source data via a linked server

-   Target tables must be on the same server as the framework, but may be in a different database

-   The framework checks source and target schemas at run-time

-   Change detection is possible if a rowversion column exists on the source table and a single column primary key exists on both source and target tables.

-   Batched operations are used when a single column primary key or a rowversion column exists on the source table.

-   The framework tolerates differences and changes in schema because it only copies matching columns, ignoring non-matching columns.

Step By Step Implementation Guide
=================================

The SQL Sync Hub is just a database. When it is installed nothing is running. It is up to you to make things happen by calling the procedures.

The work is done by calling SqlSync.CopyTable for each table that needs to be copied.

In addition you will need to consider such things as

-   Dropping and re-creating foreign keys on the target database

-   Trimming the log tables to prevent them from growing indefinitely

-   Detecting issues and alerting people

Step 1: Identify the source and target server and database.
-----------------------------------------------------------

This is a planning step. In this step you need to identify the source and target databases and servers and obtain necessary accounts and privileges.

**Source Server**: On the source server you need an account that can read the schema and data on the source database. This account needs to be used by a linked server login. The account does not need other privileges on the source.

**Target Server**: On the target server you need an account that can to read the schema and read and write data on the target database.

During implementation you will also need to be able to create a linked server and create the SqlSyncHub database on the target server, so you will need a sysadmin account on the target server. The target database can be a separate database on the target server, or you can create the target tables inside the SqlSyncHub database. The target database will typically be a reporting or staging database.

It may be useful to create a timestamp column and corresponding index on large source tables. The framework detects the presence of a timestamp column and switches to incremental mode, potentially saving a lot of data transfer.

Step 2: Create the databases
----------------------------

Three databases are involved:
* The SQL Sync Hub database
* The source database
* The target database

Create the SQL Sync Hub database by compiling the project and running the resultant DACPAC, or by running all the included scripts. (Later a pre-compiled DACPAC will be included, and a single SQL script for creation may be included).

SQL Sync Hub framework does not provide any assistance for creating the source and target databases or tables. Tools such as Management Studio scripting or Red-Gate SQL Compare can be used to generate initial table structures in the target database.

Step 3: Create the Linked Server
--------------------------------

Create a linked server on the target server, pointing to the source server.

Create a linked server login for the linked server. The login should have privileges to read the schema and data on the source database.

Step 4: Script Table Copy
-------------------------

Create a main-line-copy stored procedure that copies the required
tables.

The procedure should call SqlSync.CopyTable once for each table that needs to be kept up to date on the target database. Two common approaches are to
-	Hard-code the required tables or
-	Loop through the metadata of the target database.

Step 5: Create Scripts to Drop and Re-create Foreign Keys
---------------------------------------------------------

The copy table operations may violate foreign key constraints temporarily. This happens because parent records are be deleted while child records exist, or because child records are inserted before the corresponding parent records have been created.

To avoid foreign key constraint violation errors, the keys can be either disabled, or dropped and re-created.

The SQL Sync Hub framework assists by providing a way of creating a pair of scripts to drop and re-create the foreign keys on a target database.

Run the procedure SqlSync.ForeignKeyCreateScripts specifying the target database. This creates a pair of scripts that will drop and create the foreign keys on the target database. The scripts are stored in the SqlSync.ForeignKeyScript table.

To drop foreign keys on MyDatabase:

```
DECLARE @SQL NVARCHAR(MAX);

SELECT @SQL = DropScript
FROM SqlSyncHub.SqlSync.ForeignKeyScript
WHERE Databasename='MyDatabase';

EXEC sp_executesql @SQL;
```

To re-create foreign keys on MyDatabase:
```
DECLARE @SQL NVARCHAR(MAX);
SELECT @SQL = CreateScript
FROM SqlSyncHub.SqlSync.ForeignKeyScript
WHERE Databasename='MyDatabase';

EXEC sp_executesql @SQL;
```


Step 6: Schedule main-line-copy
-------------------------------

Schedule a call to the main-line-copy procedure.

This can be scheduled to run at any frequency using any scheduler.
Typically it would be run daily using the SQL Server Agent.

If the target database has foreign keys with checking enabled then the main-line copy should be preceded by a call to the dropkeys procedure and followed aby a call to the create keys procedure.

Step 7: Log trimming
--------------------

Records build up in the SqlSync.CopyTableLog table.

To prevent the table from growing too large you should schedule a call to a statement such as:

    DELETE FROM SqlSync.CopyTableLog WHERE LogDateTime < DATEADD(MONTH,-6,GETDATE())

Step 7: Monitoring
------------------

To achieve peace of mind without constantly looking, the system should
generate alerts if something is wrong.

Read the Monitoring Guide and develop a monitoring strategy. It should
be possible to adapt the sample _SqlSyncDemo.EmailAlert_ procedure to suit your
requirements.

Monitoring Guide
================

The CopyTable procedure will throw an error if it fails for any reason. This will typically be detected by the calling job or procedure.
One monitoring strategy is to send emails to an operator if the main job fails. Assuming the framework is being called from SQL Server Agent, this is easily done by simply setting the notifications on the job.
Another strategy is to send an email alerting people if certain conditions occur. The framework provides support monitoring the following conditions:

-   Stale Data,
-   Row Count Differences
-   Schema Differences

Constructing an alerting email requires writing code to query the framework tables. The following sections describe the available data that can be used to construct an alerting email.

Stale Data
----------

It is possible to tell when a target table was last copied by examining SqlSync.CopyTableControl.LastCopyDateTime. By comparing this with the current time it is possible to generate an alert if a table has not been copied for a defined period.

Row-count Differences
---------------------

The procedure SqlSync.ReconcileAllTables loops through all records in SqlSync.CopyTableControl and counts the records at source and target.
The actual tables are not scanned. Instead sysindexes.rows is used, which is much faster. The procedure does not output a resultset. Instead it updates the CountSrc, CountTrg and LastCountDateTime columns. The CopyTableControl table can be queried and reported in any way which suits. Rowcount differences may be expected or tolerated depending on circumstances.

Schema Differences
------------------

Sometimes it is helpful to know when a source schema diverges from the target schema. In other words we would like to know if a developer has added tables or columns to a source database and no-one has made the same changes to the target.

The framework provides a view that returns a row for every column in the source database that is not in the target. This is the SqlSync.vwSchemaChangeDetect view.

Often these differences are expected and tolerated. To suppress a column so it is not reported by the vwSchemaChangeDetect view , the column can be inserted to the table SqlSync.SchemaChangeDetectIgnore.

There is a procedure SqlSync.SchemaChangeDetectIgnoreAllCurrentDifferences which will cause any current differences to be ignored by any future selects from the view.

#Troubleshooting Guide

##CopyTableControl

The main tool for observing the status is to query the table SqlSync.CopyTableControl. This table has one row for each target table that was ever a target in a call to SqlSync.CopyTable. The columns are:


| Column|Description|
|:---|:---|
|TargetTable |Full name of the target table (key) |
|LastCopySourceTable|Full name of the source table in the last call to _SqlSync.CopyTable_|
|UseIncrementalCopy|1 Indicates that an incremental copy will be performed if a rowversion column is detected in the source metadata.<br>If this value is changed to zero the framework will not perform an incremental copy, but will instead always perform a batch or simple copy.|
|LastCopyDateTime|Time of last call to _SqlSync.CopyTable_|
|LastCopyMaxRowVersion | Source database maximum timestamp (@@DBTS) at start of last call to _SqlSync.CopyTable_|
|IsOK | 1 indicates that the last call to _SqlSync.CopyTable_ was successful.<br>0 indicates that the last call to _SqlSync.CopyTable_ has an error or is in progress.|
|Message | Shows the captured SQL error message if IsOK is 0. Otherwise null.|
| CountSrc | The count of rows in _LastCopySourceTable_. The count is made by the most recent call to _SqlSync.ReconcileAllTables_ |
| CountTrg | The count of rows in TargetTable. The count is made by the most recent call to SqlSync.ReconcileAllTables
| LastCountDateTime | The time of the most recent call to SqlSync.ReconcileAllTables|


A typical query to highlight potential problem

```
SELECT * FROM SqlSync.CopyTableControl

WHERE IsOK=0 OR CountSrc != CountTrg
```

##Copy Table Log

This is a detailed log of operations. A record is created each time data is copied from a source to target and each time data is deleted from a target. A single call to SqlSync.CopyTable may result in many records inserted to SqlSync.CopyTableLog. The columns are:

|Column| Description|
|---|------------|
|CopyTableLogID|Sequential ID (key)|
|LogDateTime  |Insertion date time|
|SourceTable  |Fully qualified name of source table|
|TargetTable  |Fully qualified name of target table|
|OperationCode|Insert, Merge, Truncate, Delete or Error|
|RowsAffected |Number of rows copied or deleted|
|Message      |Error message where applicable|

