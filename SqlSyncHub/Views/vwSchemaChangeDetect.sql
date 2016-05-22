
/********************************************************
Detect if any source/target database combination
has different columns defined between source and target.

Ignore differences stored in SchemaDriftDetectIgnore
********************************************************/
CREATE VIEW [SqlSync].[vwSchemaChangeDetect]
AS
WITH CTE_SourceTarget AS (
	SELECT
		ISNULL(PARSENAME(TargetTable,4),'') AS TargetServer,PARSENAME(TargetTable,3) AS TargetDatabase,
		ISNULL(PARSENAME(LastCopySourceTable,4), '') AS SourceServer,PARSENAME(LastCopySourceTable,3) AS SourceDatabase
	FROM SqlSync.CopyTableControl C
	GROUP BY PARSENAME(TargetTable,4),PARSENAME(TargetTable,3),	PARSENAME(LastCopySourceTable,4),PARSENAME(LastCopySourceTable,3)
)
, CTE_MetaData AS
(
SELECT
	ST.TargetServer+'.'+ST.TargetDatabase+' <= '+ST.SourceServer+'.'+ST.SourceDatabase AS DatabasePair,
	MT.MetaData AS TargetMetaData, MS.MetaData AS SourceMetaData
FROM CTE_SourceTarget ST
JOIN SqlSync.MetaData MT
		ON MT.ServerName = ST.TargetServer
		AND MT.DatabaseName = ST.TargetDatabase
JOIN SqlSync.MetaData MS
		ON MS.ServerName = ST.SourceServer
		AND MS.DatabaseName = ST.SourceDatabase
)
SELECT COALESCE(Src.DatabasePair,Targ.DatabasePair) AS DatabasePair,
	SourceTable, SourceCol,
	TargetTable, TargetCol
FROM 
(
SELECT DatabasePair, tcols.value('./TAB[1]','sysname') AS TargetTable,
		tcols.value('./COL[1]','sysname') AS TargetCol
FROM CTE_MetaData
CROSS APPLY TargetMetaData.nodes('/C') X(tcols)
) Targ
FULL OUTER JOIN
(
SELECT DatabasePair, scols.value('./TAB[1]','sysname') AS SourceTable,
		scols.value('./COL[1]','sysname') AS SourceCol
FROM CTE_MetaData
CROSS APPLY SourceMetaData.nodes('/C') X(scols)
) Src
	ON Src.SourceTable=Targ.TargetTable AND Src.SourceCol = Targ.TargetCol AND Src.DatabasePair = Targ.DatabasePair
WHERE Src.SourceCol IS NULL OR Targ.TargetCol IS NULL
EXCEPT SELECT DatabasePair,SourceTable,SourceCol,TargetTable,TargetCol FROM SqlSync.SchemaChangeDetectIgnore;

