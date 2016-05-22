
CREATE PROCEDURE [SqlSync].[SchemaChangeDetectIgnoreAllCurrentDifferences]
AS
	INSERT INTO SqlSync.SchemaChangeDetectIgnore
			( DatabasePair ,
			  SourceTable ,
			  SourceCol ,
			  TargetTable ,
			  TargetCol)		
	SELECT  DatabasePair ,
			SourceTable ,
			SourceCol ,
			TargetTable ,
			TargetCol
	FROM SqlSync.vwSchemaChangeDetect;
