
CREATE VIEW [SqlSync].[vwCopyTableControl]
AS
SELECT
		PARSENAME(TargetTable,4)AS TargetServer,
		ISNULL(PARSENAME(TargetTable,3),DB_NAME()) AS TargetDatabase,
		PARSENAME(TargetTable,2) AS TargetSchema,
		PARSENAME(TargetTable,1) AS TargetTable,

		PARSENAME(LastCopySourceTable,4)AS SourceServer,
		ISNULL(PARSENAME(LastCopySourceTable,3),DB_NAME()) AS SourceDatabase,
		PARSENAME(LastCopySourceTable,2) AS SourceSchema,
		PARSENAME(LastCopySourceTable,1) AS SourceTable,

		TargetTable AS CanonicalTargetTable,
        LastCopySourceTable AS CanonicalSourceTable,
        UseIncrementalCopy ,
        LastCopyDateTime ,
        LastCopyMaxRowVersion ,
        IsOK ,
        Message ,
        CountSrc ,
        CountTrg ,
        LastCountDateTime
FROM SqlSync.CopyTableControl