﻿# The parameters should be supplied by the Build event of the project
# in order to take macros from Visual Studio to avoid hard-coding
# the paths. To simplify the process, the project should have a 
# reference to the projects that needs to be registered, so that 
# their DLL files will be present in the $(TargetDir) macro. 
#
# Possible syntax for Post Build event of the project to invoke this:
# C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe 
#  -command "$(ProjectDir)BuildRegistryScript.ps1 
#  -config '$(ConfigurationName)' 
#  -builderAssemblyPath '$(TargetPath)' 
#  -netToolsDir '$(FrameworkSDKDir)bin\NETFX 4.6.1 Tools\' 
#  -wixToolsDir '$(SolutionDir)packages\WiX.Toolset.3.9.1208.0\tools\wix\' 
#  -sourceDir '$(TargetDir)' 
#  -targetDir '$(TargetDir)' 
#  -includeDir '$(ProjectDir)InnoSetup\Includes\'
#  -filesToExtract 'Rubberduck.dll'"
param (
	[Parameter(Mandatory=$true)][string]$config,
	[Parameter(Mandatory=$true)][string]$builderAssemblyPath,
	[Parameter(Mandatory=$true)][string]$netToolsDir,
	[Parameter(Mandatory=$true)][string]$wixToolsDir,
	[Parameter(Mandatory=$true)][string]$sourceDir,
	[Parameter(Mandatory=$true)][string]$targetDir,
	[Parameter(Mandatory=$true)][string]$includeDir,
	[Parameter(Mandatory=$true)][string]$filesToExtract
)

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value;
  Split-Path $Invocation.MyCommand.Path;
}

# Invokes a Cmd.exe shell script and updates the environment.
function Invoke-CmdScript {
  param(
    [String] $scriptName
  )
  $cmdLine = """$scriptName"" $args & set"
  & $Env:SystemRoot\system32\cmd.exe /c $cmdLine |
  select-string '^([^=]*)=(.*)$' | foreach-object {
    $varName = $_.Matches[0].Groups[1].Value
    $varValue = $_.Matches[0].Groups[2].Value
    set-item Env:$varName $varValue
  }
}

# Returns the current environment.
function Get-Environment {
  get-childitem Env:
}

# Restores the environment to a previous state.
function Restore-Environment {
  param(
    [parameter(Mandatory=$TRUE)]
      [System.Collections.DictionaryEntry[]] $oldEnv
  )
  # Remove any added variables.
  compare-object $oldEnv $(Get-Environment) -property Key -passthru |
  where-object { $_.SideIndicator -eq "=>" } |
  foreach-object { remove-item Env:$($_.Name) }
  # Revert any changed variables to original values.
  compare-object $oldEnv $(Get-Environment) -property Value -passthru |
  where-object { $_.SideIndicator -eq "<=" } |
  foreach-object { set-item Env:$($_.Name) $_.Value }
}

Set-StrictMode -Version latest;
$ErrorActionPreference = "Stop";
$DebugUnregisterRun = $false;

try
{
	# Allow multiple DLL files to be registered if necessary
	$separator = "|";
	$option = [System.StringSplitOptions]::RemoveEmptyEntries;
	$files = $filesToExtract.Split($separator, $option);

	foreach($file in $files)
	{
		$dllFile = [System.String]$file;
		$idlFile = [System.String]($file -replace ".dll", ".idl");
		$tlb32File = [System.String]($file -replace ".dll", ".x32.tlb");
		$tlb64File = [System.String]($file -replace ".dll", ".x64.tlb");

		$sourceDll = $sourceDir + $file;
		$targetDll = $targetDir + $file;
		$sourceTlb32 = $sourceDir + $tlb32File;
		$targetTlb32 = $targetDir + $tlb32File;
		$sourceTlb64 = $sourceDir + $tlb64File;
		$targetTlb64 = $targetDir + $tlb64File;
		$dllXml = $targetDll + ".xml";
		$tlbXml = $targetTlb32 + ".xml";

		# Use for debugging issues with passing parameters to the external programs
		# Note that it is not legal to have syntax like `& $cmdIncludingArguments` or `& $cmd $args`
		# For simplicity, the arguments are pass in literally.
		# & "C:\GitHub\Rubberduck\Rubberduck\Rubberduck.Deployment\echoargs.exe" ""$sourceDll"" /win32 /out:""$sourceTlb"";
		
		[System.Reflection.Assembly]::LoadFrom($builderAssemblyPath);

		$devPath = Resolve-Path -Path "C:\Program Files*\Microsoft Visual Studio\*\*\Common*\Tools\VsDevCmd.bat";
		if($devPath)
		{
			$idlGenerator = New-Object Rubberduck.Deployment.IdlGeneration.IdlGenerator;
		
			$idl = $idlGenerator.GenerateIdl($sourceDll);
			$encoding = New-Object System.Text.UTF8Encoding $true;
			[System.IO.File]::WriteAllLines($idlFile, $idl, $encoding);
		
			$origEnv = Get-Environment
			try {
				Invoke-CmdScript "$devPath";
		
				& "midl.exe" ""$idlFile"" /win32 /out ""$targetDir"" /tlb ""$tlb32File"";
				& "midl.exe" ""$idlFile"" /amd64 /out ""$targetDir"" /tlb ""$tlb64File"";
			} catch {
				throw;
			} finally {
				Restore-Environment $origEnv;
			}
		}
		else
		{
			Write-Warning "Cannot locate the VsDevCmd.bat to initialize C++ build tools; falling back to tlbexp.exe....";
			$cmd = "{0}tlbexp.exe" -f $netToolsDir;
			& $cmd ""$sourceDll"" /win32 /out:""$sourceTlb32"";
			& $cmd ""$sourceDll"" /win64 /out:""$sourceTlb64"";
		}

		$cmd = "{0}heat.exe" -f $wixToolsDir;
		& $cmd file ""$sourceDll"" -out ""$dllXml"";
		& $cmd file ""$sourceTlb32"" -out ""$tlbXml"";
		
		$builder = New-Object Rubberduck.Deployment.Builders.RegistryEntryBuilder;
	
		$entries = $builder.Parse($tlbXml, $dllXml);

		# For debugging
		# $entries | Format-Table | Out-String |% {Write-Host $_};
		
		$writer = New-Object Rubberduck.Deployment.Writers.InnoSetupRegistryWriter;
		$content = $writer.Write($entries, $dllFile, $tlb32File, $tlb64File);
		
		# The file must be encoded in UTF-8 BOM
		$regFile = ($includeDir + ($file -replace ".dll", ".reg.iss"));
		$encoding = New-Object System.Text.UTF8Encoding $true;
		[System.IO.File]::WriteAllLines($regFile, $content, $encoding);
		$content = $null;

		# Register the debug build on the local machine
		if($config -eq "Debug")
		{
			if(!$DebugUnregisterRun) 
			{
				# First see if there are registry script from the previous build
				# If so, execute them to delete previous build's keys (which may
				# no longer exist for the current build and thus won't be overwritten)
				$dir = ((Get-ScriptDirectory) + "\LocalRegistryEntries");
				$regFileDebug = $dir + "\DebugRegistryEntries.reg";

				if (Test-Path -Path $dir -PathType Container)
				{
					if (Test-Path -Path $regFileDebug -PathType Leaf)
					{
						$datetime = Get-Date;
						if ([Environment]::Is64BitOperatingSystem)
						{
							& reg.exe import $regFileDebug /reg:32;
							& reg.exe import $regFileDebug /reg:64;
						}
						else 
						{
							& reg.exe import $regFileDebug;
						}
						& reg.exe import ($dir + "\RubberduckAddinRegistry.reg");
						Move-Item -Path $regFileDebug -Destination ($regFileDebug + ".imported_" + $datetime.ToUniversalTime().ToString("yyyyMMddHHmmss") + ".txt" );
					}
				}
				else
				{
					New-Item $dir -ItemType Directory;
				}

				$DebugUnregisterRun = $true;
			}

			# NOTE: The local writer will perform the actual registry changes; the return
			# is a registry script with deletion instructions for the keys to be deleted
			# in the next build.
			$writer = New-Object Rubberduck.Deployment.Writers.LocalDebugRegistryWriter;
			$content = $writer.Write($entries, $dllFile, $tlb32File, $tlb64File);

			$encoding = New-Object System.Text.ASCIIEncoding;
			[System.IO.File]::AppendAllText($regFileDebug, $content, $encoding);
		}

		Write-Host "Finished processing '$file'";
		Write-Host "";
	}
	
	Write-Host "Finished processing all files";
}
catch
{
	Write-Error ($_);
	# Cause the build to fail
	throw;
}

# for debugging locally
# Write-Host "Press any key to continue...";
# Read-Host -Prompt "Press Enter to continue";

