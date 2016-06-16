# Script database via dacpac
# https://msdn.microsoft.com/en-us/hh550080(v=vs.103).aspx
#
# The SqlSyncHub.dacpac file is generated automatically by Visual Studio build
# But we want to create a stand-alone SQL script for people who dont want to deal with DACPAC management
# That requires this script to generate SqlSyncHub_Create.sql

Clear-Host
$ExeFolder = "D:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\120\"
#$ExeFolder = "C:\Program Files (x86)\Microsoft SQL Server\120\DAC\bin\";
$WorkFolder = "I:\SSDT"
$DatabaseServer = "DEV-SQL03.datafocus.com.au"
$DatabaseName = "SqlSyncHub"

$cmd = $ExeFolder + "SqlPackage.exe"


$AllArgs = @()
#$AllArgs += "/help:true"
$AllArgs += "/Action:Extract"
$AllArgs += "/SourceServerName:$DatabaseServer"
$AllArgs += "/SourceDatabaseName:$DatabaseName"
$AllArgs += "/SourceEncryptConnection:false"
$AllArgs += "/TargetFile:$WorkFolder\$DatabaseName.dacpac"
 
& $cmd $AllArgs


$AllArgs = @()
#$AllArgs += "/help:true"
$AllArgs += "/Action:Script"
$AllArgs += "/SourceServerName:$DatabaseServer"
$AllArgs += "/SourceFile:$WorkFolder\$DatabaseName.dacpac"
$AllArgs += "/TargetServerName:$DatabaseServer"
$AllArgs += "/TargetDatabaseName:model"
$AllArgs += "/op:$WorkFolder\$DatabaseName" + "_Create0.sql"
$AllArgs += "/p:CreateNewDatabase=False"
$AllArgs += "/p:ExcludeObjectTypes=Users,DatabaseRoles"
$AllArgs += "/p:DropObjectsNotInSource=False"
$AllArgs += "/p:ScriptDatabaseOptions=False"
$AllArgs += "/p:CommentOutSetVarDeclarations=False"
$AllArgs += "/p:BlockOnPossibleDataLoss=True"


& $cmd $AllArgs
cat $WorkFolder\SqlSyncHub_Create0.sql | 
    % { $_ -replace “:setvar DatabaseName ""model""”,”:setvar DatabaseName ""$DatabaseName""” } |
    % { $_ -replace “:setvar DefaultFilePrefix ""model""”,”” }  > $WorkFolder\SqlSyncHub_Create.sql
