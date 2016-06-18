# Script database via dacpac
# https://msdn.microsoft.com/en-us/hh550080(v=vs.103).aspx
#
# The SqlSyncHub.dacpac file is generated automatically by Visual Studio build
# But we want to create a stand-alone SQL script for people who dont want to deal with DACPAC management
# That requires this script to generate SqlSyncHub_Create.sql
param([string]$OutputPath = "bin\debug\")

Clear-Host
$ExeFolder = "D:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\120\"
#$ExeFolder = "C:\Program Files (x86)\Microsoft SQL Server\120\DAC\bin\";
$DatabaseName = "SqlSyncHub"

$OutputPath = $PSScriptRoot + "\" + $OutputPath.Replace("'", "")
$OutputPath1 = "$OutputPath$DatabaseName" + "_Create0.sql"
$SourceFile = "$OutputPath$DatabaseName.dacpac"
$TargetFile = $PSScriptRoot + "\Empty$DatabaseName.dacpac"

$cmd = $ExeFolder + "SqlPackage.exe"

$AllArgs = @()
#$AllArgs += "/help:true"
$AllArgs += "/Action:Script"
$AllArgs += "/SourceFile:$SourceFile"
$AllArgs += "/TargetFile:$TargetFile"
$AllArgs += "/TargetDatabaseName:$DatabaseName"
$AllArgs += "/op:$OutputPath1"
$AllArgs += "/p:CreateNewDatabase=False"
$AllArgs += "/p:ExcludeObjectTypes=Users,DatabaseRoles"
$AllArgs += "/p:DropObjectsNotInSource=False"
$AllArgs += "/p:ScriptDatabaseOptions=False"
$AllArgs += "/p:CommentOutSetVarDeclarations=False"
$AllArgs += "/p:BlockOnPossibleDataLoss=True"

write "Generating database create script from $SourceFile compared to $TargetFile"

& $cmd $AllArgs

