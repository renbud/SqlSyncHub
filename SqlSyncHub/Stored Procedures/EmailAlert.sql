/*******************************************
Send an email alert if 
1. Dates are stale
2. Rowcounts are different
3. Schemas have changed

e.g
EXEC SqlSyncDemo.EmailAlert @recipients = 'dilbert@demo.com;dogbert@demo.com'
*******************************************/
CREATE PROCEDURE SqlSyncDemo.EmailAlert
	@recipients VARCHAR(500)
AS
BEGIN
	SET NOCOUNT ON;

	EXEC SqlSyncDemo.ReconcileTables; -- Set up rowcounts in SqlSync.CopyTableControl

	DECLARE @subj VARCHAR(8000)='SQL Sync Hub - ' + @@servername + '.' + DB_NAME() + ' – Notification / Alert';
	DECLARE @mailprofile sysname = NULL;	-- Set a profile here, otherwise this uses the 1st available profile
	DECLARE @msg VARCHAR(MAX) = null;
	DECLARE @MaxStaleDays INT=2;
	DECLARE @MaxRowDifference FLOAT = 0.002;

	/******************************
	Rowcount difference detection
	*******************************/
	DECLARE @msgRC VARCHAR(MAX);
	SELECT @msgRC = ISNULL(@msgRC,'') +
		'<tr><td>' + ISNULL(PARSENAME(TargetTable,3)+'.','') +ISNULL(PARSENAME(TargetTable,2)+'.','') + PARSENAME(TargetTable,1) + 
		'</td><td>' + CONVERT(VARCHAR(10),CountSrc) +
		'</td><td>' + CONVERT(VARCHAR(10),CountTrg) +
		'</td><td>' + CONVERT(VARCHAR(10),CountSrc-CountTrg) + '</td></tr>'
	FROM SqlSync.CopyTableControl
	WHERE isnull(CountSrc,0)<>isnull(CountTrg,0)
		AND (ABS(isnull(CountSrc,0)-isnull(CountTrg,0)) / (isnull(CountSrc,0)+0.1)) > @MaxRowDifference;

	IF @msgRC IS NOT NULL
	SELECT @msg= ISNULL(@msg,'')+CHAR(10) +'<h2>Rowcounts Significantly Different</h2>'+CHAR(10) +
		'<table><tr><th>Table</th><th>Source Rows</th><th>Target Rows</th><th>Difference</th></tr>' +
		@msgRC + '</table>'+CHAR(10);

	SELECT @msg;

	/******************************
	Stale dates detection
	*******************************/
	DECLARE @msgDates VARCHAR(4000);
	;WITH CTE_Dates AS (
		SELECT MIN(LastCopyDateTime) AS KeyDate, 'Oldest Copy Date' AS KeyDateName
		FROM SqlSync.CopyTableControl
		UNION ALL
		select  MIN(LastCountDateTime) AS KeyDate, 'Oldest Count Date' AS KeyDateName
		FROM SqlSync.CopyTableControl
	)
	SELECT @msgDates = ISNULL(@msgDates, '') + '<p>' +	KeyDateName + ': ' + CONVERT(VARCHAR(20), KeyDate, 107) + '</p>'
	FROM CTE_Dates
	WHERE EXISTS
	(SELECT 1 FROM CTE_Dates WHERE KeyDate < DATEADD(DAY,-@MaxStaleDays,GETDATE()))

	IF @msgDates IS NOT NULL
		SELECT @msg = ISNULL(@msg,'') + '<h2>Stale Dates</h2>' + CHAR(10) + @msgDates;
	--SELECT @msg

	/****************************
	Schema change detection
	*****************************/
	DECLARE @msgSchema VARCHAR(MAX);
	;WITH CTE_SchemaChange AS (
		SELECT '<tr><td>' + DatabasePair + '</td><td>' +
			CASE WHEN TargetTable IS NULL
				THEN SourceTable+'.'+SourceCol + '</td><td>exists on source but not on target database'
				ELSE TargetTable+'.'+TargetCol + '</td><td>exists on target but not on source database'
			END + '</td></tr>'
			AS Msg          
		FROM SqlSync.vwSchemaChangeDetect
	)
	SELECT @msgSchema= ISNULL(@msgSchema, '') +	Msg
				FROM CTE_SchemaChange;

	IF @msgSchema IS NOT NULL
	SELECT @msg= ISNULL(@msg,'')+CHAR(10) +'<h2>Schema Change</h2>'+CHAR(10) +
		'<table><tr><th>Servers</th><th>Table.Column</th><th>Message</th></tr>' +
		@msgSchema + '</table>';

	/***************************************
	Finalise the message by wrapping in html
	***************************************/
	SELECT @msg='<html>' +CHAR(10) +
		'<head>
		<style>
		th {color:green;}
		td {color:blue;}
		table,th,td {
			border: 1px solid black;border-collapse:collapse;padding:0px 5px 0px 5px
		}
		</style>
		</head>
		<h1>SQL Sync Hub – Notification</h1>
		' +
		@Msg +
		CHAR(10) + '</html>'
	SELECT @msg

	/***************************
	Send the message
	****************************/
	-- No standard mail profile? use 1st profile
	IF @mailprofile IS NULL
		SELECT TOP 1 @mailprofile= name FROM msdb.dbo.sysmail_profile;

	IF @msg IS NOT NULL AND @mailprofile IS NOT NULL
	BEGIN  
	EXEC msdb.dbo.sp_send_dbmail
		@profile_name = @mailprofile,
		@recipients = @recipients,
		@body = @msg,
		--@importance='High',
		@subject = @subj,
		@body_format = 'HTML' ;
	END
END
