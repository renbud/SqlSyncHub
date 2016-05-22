
/* =============================================
-- Author:		Renato
-- Create date: 
-- Description:	Return text surrounded by singe quotes. (internal quotes are escaped by doubling , i.e. dog's becomes dog''s

e.g.
SELECT SqlSync.fnQuoteSqlText('test ''this'' and that'); --> 'test ''this'' and that'
-- ============================================= */
CREATE FUNCTION [SqlSyncInternal].[fnQuoteSqlText] (@txt nvarchar(max))
RETURNS nvarchar(max)
AS
BEGIN
	DECLARE @ret nvarchar(max);
	SET @ret = '''' + replace(@txt, '''', '''''') + '''';
	return @ret;
END

