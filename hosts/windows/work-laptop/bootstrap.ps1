[CmdletBinding()]
param(
    [switch]$ApplyPackages,
    [switch]$ApplyPowerToys,
    [switch]$InstallTerminalFragment,
    [switch]$ExportPowerToysSchemas,
    [switch]$InstallWinGetDscModule,
    [switch]$AcceptAgreements
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSCommandPath
$PackageConfig = Join-Path $Root "configuration.dsc.yaml"
$PowerToysConfig = Join-Path $Root "powertoys.dsc.yaml"
$TerminalFragment = Join-Path $Root "terminal-settings.fragment.json"

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-PowerToysDscPath {
    $candidates = @()

    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "PowerToys\PowerToys.DSC.exe"
    }

    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "PowerToys\PowerToys.DSC.exe"
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) {
        $candidates += Join-Path $programFilesX86 "PowerToys\PowerToys.DSC.exe"
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $command = Get-Command "PowerToys.DSC.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Invoke-WinGetConfigure {
    param([Parameter(Mandatory)][string]$ConfigPath)

    if (-not (Test-CommandExists "winget")) {
        throw "winget was not found. Install or enable Windows Package Manager through the approved corporate path."
    }

    $arguments = @("configure", "-f", $ConfigPath)
    if ($AcceptAgreements) {
        $arguments += "--accept-configuration-agreements"
    }

    & winget @arguments
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()]$Value
    )

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        $InputObject.$Name = $Value
    } else {
        Add-Member -InputObject $InputObject -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Merge-TerminalSettingsFragment {
    if (-not $env:LOCALAPPDATA) {
        throw "LOCALAPPDATA is not set; cannot locate Windows Terminal settings."
    }

    $settingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        throw "Windows Terminal settings were not found at $settingsPath. Start Windows Terminal once, then retry."
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $fragment = Get-Content -LiteralPath $TerminalFragment -Raw | ConvertFrom-Json

    $backupPath = "$settingsPath.$(Get-Date -Format yyyyMMddHHmmss).bak"
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath

    foreach ($property in @("copyOnSelect", "copyFormatting", "trimBlockSelection", "trimPaste")) {
        Set-JsonProperty -InputObject $settings -Name $property -Value $fragment.$property
    }

    if (-not ($settings.PSObject.Properties.Name -contains "profiles") -or $null -eq $settings.profiles) {
        Set-JsonProperty -InputObject $settings -Name "profiles" -Value ([pscustomobject]@{})
    }

    if (-not ($settings.profiles.PSObject.Properties.Name -contains "defaults") -or $null -eq $settings.profiles.defaults) {
        Set-JsonProperty -InputObject $settings.profiles -Name "defaults" -Value ([pscustomobject]@{})
    }

    foreach ($profileDefault in $fragment.profiles.defaults.PSObject.Properties) {
        Set-JsonProperty -InputObject $settings.profiles.defaults -Name $profileDefault.Name -Value $profileDefault.Value
    }

    $actions = @()
    if (($settings.PSObject.Properties.Name -contains "actions") -and $null -ne $settings.actions) {
        $actions = @($settings.actions)
    }

    foreach ($newAction in @($fragment.actions)) {
        if ($newAction.PSObject.Properties.Name -contains "keys") {
            $actions = @($actions | Where-Object {
                -not (($_.PSObject.Properties.Name -contains "keys") -and $_.keys -eq $newAction.keys)
            })
        }

        $actions += $newAction
    }

    Set-JsonProperty -InputObject $settings -Name "actions" -Value $actions
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    Write-Host "Updated Windows Terminal settings."
    Write-Host "Backup written to $backupPath"
}

function Export-PowerToysSchemas {
    $powerToysDsc = Get-PowerToysDscPath
    if (-not $powerToysDsc) {
        throw "PowerToys.DSC.exe was not found. Install PowerToys first."
    }

    $schemaDir = Join-Path $Root "schemas"
    New-Item -ItemType Directory -Path $schemaDir -Force | Out-Null

    & $powerToysDsc modules --resource settings |
        Set-Content -LiteralPath (Join-Path $schemaDir "modules.txt") -Encoding UTF8

    $modules = @(
        "App",
        "FancyZones",
        "PowerLauncher",
        "ColorPicker",
        "PowerRename",
        "KeyboardManager",
        "TextExtractor",
        "Workspaces",
        "EnvironmentVariables",
        "ShortcutGuide"
    )

    foreach ($module in $modules) {
        try {
            & $powerToysDsc schema --resource settings --module $module |
                Set-Content -LiteralPath (Join-Path $schemaDir "$module.schema.json") -Encoding UTF8
            Write-Host "Exported schema for $module"
        } catch {
            Write-Warning "Could not export schema for $module`: $_"
        }
    }
}

if (-not ($ApplyPackages -or $ApplyPowerToys -or $InstallTerminalFragment -or $ExportPowerToysSchemas -or $InstallWinGetDscModule)) {
    Write-Host "Work laptop Windows profile checks"
    Write-Host "winget available: $(Test-CommandExists "winget")"
    Write-Host "PowerToys.DSC.exe: $(Get-PowerToysDscPath)"
    Write-Host ""
    Write-Host "Apply reviewed pieces explicitly:"
    Write-Host "  .\bootstrap.ps1 -ApplyPackages"
    Write-Host "  .\bootstrap.ps1 -ApplyPowerToys"
    Write-Host "  .\bootstrap.ps1 -InstallTerminalFragment"
    Write-Host "  .\bootstrap.ps1 -ExportPowerToysSchemas"
    exit 0
}

if ($InstallWinGetDscModule) {
    if (-not (Test-CommandExists "Install-Module")) {
        throw "Install-Module was not found. Install PowerShellGet through the approved corporate path."
    }

    Install-Module Microsoft.WinGet.DSC -Scope CurrentUser -Force
}

if ($ApplyPackages) {
    Invoke-WinGetConfigure -ConfigPath $PackageConfig
}

if ($ApplyPowerToys) {
    Invoke-WinGetConfigure -ConfigPath $PowerToysConfig
}

if ($InstallTerminalFragment) {
    Merge-TerminalSettingsFragment
}

if ($ExportPowerToysSchemas) {
    Export-PowerToysSchemas
}
