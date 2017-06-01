#This script is based on https://github.com/tobania/VSTS.Extension.EntityFrameworkMigrations
[CmdletBinding()]
param(
)

$WorkingFolder = Get-VstsInput -Name "WorkingFolder" -Require
$BinFolder = Get-VstsInput -Name "BinFolder" -Require
$MigrateExeFolder = Get-VstsInput -Name "MigrateExeFolder" -Require
$TargetAssembly = Get-VstsInput -Name "TargetAssembly" -Require
$ConfigurationFile = Get-VstsInput -Name "ConfigurationFile"
$ConnectionString = Get-VstsInput -Name "ConnectionString"
$ConnectionProviderName = Get-VstsInput -Name "ConnectionProviderName"
$TargetDbContextConfiguration = Get-VstsInput -Name "TargetDbContextConfiguration"
$ConnectedServiceNameSelector = Get-VstsInput -Name "ConnectedServiceNameSelector"
$ConnectedServiceName = Get-VstsInput -Name "ConnectedServiceName"
$ConnectedServiceNameARM = Get-VstsInput -Name "ConnectedServiceNameARM"
$IpDetectionMethod = Get-VstsInput -Name "IpDetectionMethod"
$StartIPAddress = Get-VstsInput -Name "StartIPAddress"
$EndIPAddress = Get-VstsInput -Name "EndIPAddress"
$ServerName = Get-VstsInput -Name "ServerName"
$SqlUsername = Get-VstsInput -Name "SqlUsername"
$SqlPassword = Get-VstsInput -Name "SqlPassword"
$UseVerbose = Get-VstsInput -Name "UseVerbose"

. "$PSScriptRoot\Utility.ps1"

	if($VerbosePreference -eq "SilentlyContinue" -And $UseVerbose -eq "true") {
        $VerbosePreference = "continue"
    }

	Write-Host "Preparing script... (Verbose = $UseVerbose)"

	# Check if Entity Framework DLLs exist inside the $BinFolder
	Write-Host "Checking if $WorkingFolder\$BinFolder\EntityFramework.dll exists..."
	if( -Not (Test-Path "$WorkingFolder\$BinFolder\EntityFramework.dll")){
		Write-Error "EntityFramework.dll was not found in the provided bin folder"
		exit 1
	}

	# Check if the provided assembly exists inside the $BinFolder
	Write-Host "Checking if $WorkingFolder\$BinFolder\$TargetAssembly exists..."
	if( -Not (Test-Path "$WorkingFolder\$BinFolder\$TargetAssembly")){
		Write-Error "$TargetAssembly was not found inside $BinFolder"
		exit 2
	}

	# Check if migrate exists in the build artifacts
	Write-Host "Checking if $WorkingFolder\$MigrateExeFolder\migrate.exe exists..."
	if( -Not (Test-Path "$WorkingFolder\$MigrateExeFolder\migrate.exe")){
		Write-Error "$WorkingFolder\$MigrateExeFolder\migrate.exe was not found."
		exit 3
	}
	
	if ( -Not [string]::IsNullOrWhiteSpace($ConfigurationFile)) {		
		# Check if configuration file exists
		Write-Host "Checking if $WorkingFolder\$ConfigurationFile exists..."
		if( -Not (Test-Path "$WorkingFolder\$ConfigurationFile")){
			Write-Error "$WorkingFolder\$ConfigurationFile was not found."
			exit 4
		}
	}
	#Copy migrate.exe to the bin folder
	Write-Host "Copying $WorkingFolder\$MigrateExeFolder\migrate.exe to $WorkingFolder\$BinFolder"
	Copy-Item "$WorkingFolder\$MigrateExeFolder\migrate.exe" -Destination "$WorkingFolder\$BinFolder"

	# If we are running on .NET 4.0, we also have to copy over a configuration file for migrate.exe
	Write-Host "Checking if $WorkingFolder\$MigrateExeFolder\migrate.exe.config exists (in case of .NET 4.0)"
	if(Test-Path "$WorkingFolder\$MigrateExeFolder\migrate.exe.config"){
		Write-Host "Copying $WorkingFolder\$MigrateExeFolder\migrate.exe.config to $WorkingFolder\$BinFolder"
		Copy-Item "$WorkingFolder\$MigrateExeFolder\migrate.exe.config" -Destination "$WorkingFolder\$BinFolder"
	}

	Write-Host "Working inside: $WorkingFolder"
	Write-Host "Bin folder: $WorkingFolder\$BinFolder"
	Write-Host "Assembly containing migrations: $TargetAssembly"
	Write-Host "Using DbContext configuration: $TargetDbContextConfiguration"
	Write-Host "Using configuration file: $WorkingFolder\$ConfigurationFile"
	Write-Host "MigrateExe folder: $MigrateExeFolder"

	Write-Host "Finished preparations"
	
	Write-Host "Building Migrate Command"
	$baseCommand = """$WorkingFolder\$BinFolder\migrate.exe"" $TargetAssembly "
	if(-Not [string]::IsNullOrWhiteSpace($TargetDbContextConfiguration)){		
		$baseCommand = $baseCommand + " $TargetDbContextConfiguration "
	}
	if(-Not [string]::IsNullOrWhiteSpace($ConfigurationFile)) {
		$baseCommand = $baseCommand + "/startupConfigurationFile=""$WorkingFolder\$ConfigurationFile"""
	}
	if(-Not [string]::IsNullOrWhiteSpace($ConnectionString)) {
		$baseCommand = $baseCommand + " /connectionString=""$ConnectionString"" /connectionProviderName=""$ConnectionProviderName"""
	}
	if($UseVerbose -eq "true") {
		$baseCommand = $baseCommand + " /verbose"
	}
	
	if($IpDetectionMethod -ne "None") {
		Write-Host "Setting database firewall rules for $ServerName" 
		if ($ConnectedServiceNameSelector -eq "ConnectedServiceNameARM")
		{
			$ConnectedServiceName = $ConnectedServiceNameARM
		}
		$ServerName = $ServerName.ToLower()
		# Checks for the very basic consistency of the Server Name
		Check-ServerName $ServerName

		$serverFriendlyName = $ServerName.split(".")[0]
		Write-Host "Server friendly name is $serverFriendlyName"
		
		# Getting endpoint used for the task
		$endpoint = Get-Endpoint -connectedServiceName $connectedServiceName	
		$ipAddressRange = @{}
		if($IpDetectionMethod -eq "AutoDetect")
		{
			$ipAddressRange = Get-AgentIPRange -serverName $ServerName -sqlUsername $SqlUsername -sqlPassword $SqlPassword
		}
		else 
		{
			$ipAddressRange.StartIPAddress = $StartIpAddress
			$ipAddressRange.EndIPAddress = $EndIpAddress
		}

		Write-Host ($ipAddressRange | Format-List | Out-String)

		# creating firewall rule for agent on sql server, if it is not able to connect or iprange is selected
		if($ipAddressRange.Count -ne 0)
		{
			$firewallSettings = Create-AzureSqlDatabaseServerFirewallRule -startIP $ipAddressRange.StartIPAddress -endIP $ipAddressRange.EndIPAddress -serverName $serverFriendlyName -endpoint $endpoint
			Write-Host ($firewallSettings | Format-List | Out-String)

			$firewallRuleName = $firewallSettings.RuleName
			$isFirewallConfigured = $firewallSettings.IsConfigured
		}
	}
	Write-Host "Running $baseCommand"
	iex "& $baseCommand"
	$MigrateExitCode = $LASTEXITCODE
	Write-Host "Migration completed"
	if( -Not [string]::IsNullOrWhiteSpace($firewallRuleName)) {
		Write-Host "Cleaning up Firewall rule"	
		Delete-AzureSqlDatabaseServerFirewallRule -serverName $serverFriendlyName -endpoint $endpoint -firewallRuleName $firewallRuleName -deleteFirewallRule "true" -isFirewallConfigured "true"
	}
		
	#Cleanup migrate from bin folder
	Write-Host "Cleaning $WorkingFolder\$BinFolder\migrate.exe"
	Remove-Item "$WorkingFolder\$BinFolder\migrate.exe"

	if(Test-Path "$WorkingFolder\$BinFolder\migrate.exe.config"){
		Write-Host "Cleaning $WorkingFolder\$BinFolder\migrate.exe.config"
		Remove-Item "$WorkingFolder\$BinFolder\migrate.exe.config"
	}

	if($MigrateExitCode -gt 0){
		Write-Error "Migrate.exe failed with error code $MigrateExitCode"
		exit 5
	}

	Write-Host "Migrations applied to database."

