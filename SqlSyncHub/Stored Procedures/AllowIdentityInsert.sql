CREATE PROCEDURE [SqlSyncInternal].[AllowIdentityInsert]
	@TargetTable sysname,
	@SQLString NVARCHAR(MAX) OUTPUT
AS
BEGIN
		DECLARE @SqlIdOn NVARCHAR(4000), @SqlIdOff NVARCHAR(4000), @HasIdentity BIT = 0;
		EXEC SqlSyncInternal.GetIdentityStatus @TargetTable, @HasIdentity OUTPUT;
		IF @HasIdentity = 1
		BEGIN
			SET @SqlIdOn = N'SET IDENTITY_INSERT ' +  SqlSync.fnQuoteObjectName(@TargetTable, 0) + N' ON;'
			SET @SqlIdOff = N'SET IDENTITY_INSERT ' +  SqlSync.fnQuoteObjectName(@TargetTable, 0) + N' OFF;'
			SET @SQLString = @SqlIdOn + CHAR(10) + @SQLString + CHAR(10) + @SqlIdOff;
		END
END