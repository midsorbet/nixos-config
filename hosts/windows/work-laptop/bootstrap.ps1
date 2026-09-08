[CmdletBinding()]
param(
    [switch]$ApplyPackages,
    [switch]$ApplyPowerToys,
    [switch]$InstallCommandPaletteFragment,
    [switch]$InstallTerminalFragment,
    [switch]$ExportPowerToysSchemas,
    [switch]$AcceptAgreements
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSCommandPath
$PackageConfig = Join-Path $Root "configuration.dsc.yaml"
$PowerToysConfig = Join-Path $Root "powertoys.dsc.yaml"
$CommandPaletteFragment = Join-Path $Root "command-palette.settings.fragment.json"
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

    $versionOutput = & winget --version | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '(?<version>\d+\.\d+(?:\.\d+){0,2})') {
        throw "WinGet DSC v3 prerequisite check failed: could not determine the installed WinGet version."
    }

    $installedVersion = [version]$Matches.version
    if ($installedVersion -lt [version]"1.11") {
        throw "WinGet DSC v3 requires WinGet 1.11 or later; found $installedVersion. Update App Installer through the approved corporate path."
    }

    $arguments = @("configure", "-f", $ConfigPath)
    if ($AcceptAgreements) {
        $arguments += "--accept-configuration-agreements"
    }

    & winget @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet configuration failed for $ConfigPath with exit code $LASTEXITCODE."
    }
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

function Merge-JsonObjectProperties {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)]$Fragment
    )

    foreach ($property in $Fragment.PSObject.Properties) {
        $targetProperty = $Target.PSObject.Properties[$property.Name]
        if ($null -ne $targetProperty -and
            $targetProperty.Value -is [pscustomobject] -and
            $property.Value -is [pscustomobject]) {
            Merge-JsonObjectProperties -Target $targetProperty.Value -Fragment $property.Value
        } else {
            Set-JsonProperty -InputObject $Target -Name $property.Name -Value $property.Value
        }
    }
}

function Merge-CommandPaletteSettingsFragment {
    if (-not $env:LOCALAPPDATA) {
        throw "LOCALAPPDATA is not set; cannot locate Command Palette settings."
    }

    $settingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        throw "Command Palette settings were not found at $settingsPath. Start Command Palette once, close it, then retry."
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $fragment = Get-Content -LiteralPath $CommandPaletteFragment -Raw | ConvertFrom-Json

    $backupPath = "$settingsPath.$(Get-Date -Format yyyyMMddHHmmss).bak"
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath

    foreach ($property in $fragment.PSObject.Properties) {
        Set-JsonProperty -InputObject $settings -Name $property.Name -Value $property.Value
    }

    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    Write-Host "Updated Command Palette settings. Restart Command Palette to load them."
    Write-Host "Backup written to $backupPath"
}

function Merge-TerminalSettingsFile {
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$FragmentPath
    )

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        throw "Windows Terminal settings were not found at $SettingsPath. Start Windows Terminal once, then retry."
    }

    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    $fragment = Get-Content -LiteralPath $FragmentPath -Raw | ConvertFrom-Json

    if ($fragment.PSObject.Properties.Name -notcontains "theme" -or
        $fragment.PSObject.Properties.Name -notcontains "profiles" -or
        $null -eq $fragment.profiles -or
        $fragment.profiles.PSObject.Properties.Name -notcontains "defaults" -or
        $null -eq $fragment.profiles.defaults -or
        $fragment.PSObject.Properties.Name -notcontains "schemes" -or
        $fragment.PSObject.Properties.Name -notcontains "actions") {
        throw "Windows Terminal fragment is missing theme, profiles.defaults, schemes, or actions."
    }

    $fragmentSchemeNames = @{}
    foreach ($scheme in @($fragment.schemes)) {
        if ($null -eq $scheme -or
            $scheme.PSObject.Properties.Name -notcontains "name" -or
            [string]::IsNullOrWhiteSpace([string]$scheme.name) -or
            $fragmentSchemeNames.ContainsKey([string]$scheme.name)) {
            throw "Windows Terminal fragment schemes must have unique, non-empty names."
        }
        $fragmentSchemeNames[[string]$scheme.name] = $true
    }

    $fragmentActionKeys = @{}
    foreach ($action in @($fragment.actions)) {
        if ($null -eq $action -or
            $action.PSObject.Properties.Name -notcontains "keys" -or
            [string]::IsNullOrWhiteSpace([string]$action.keys) -or
            $fragmentActionKeys.ContainsKey([string]$action.keys)) {
            throw "Windows Terminal fragment actions must have unique, non-empty keys."
        }
        $fragmentActionKeys[[string]$action.keys] = $true
    }

    $originalJson = $settings | ConvertTo-Json -Depth 100

    foreach ($property in @("copyOnSelect", "copyFormatting", "trimBlockSelection", "trimPaste", "theme")) {
        if ($fragment.PSObject.Properties.Name -contains $property) {
            Set-JsonProperty -InputObject $settings -Name $property -Value $fragment.$property
        }
    }

    if ($settings.PSObject.Properties.Name -notcontains "profiles" -or $null -eq $settings.profiles) {
        Set-JsonProperty -InputObject $settings -Name "profiles" -Value ([pscustomobject]@{})
    }
    if ($settings.profiles.PSObject.Properties.Name -notcontains "defaults" -or $null -eq $settings.profiles.defaults) {
        Set-JsonProperty -InputObject $settings.profiles -Name "defaults" -Value ([pscustomobject]@{})
    }
    Merge-JsonObjectProperties -Target $settings.profiles.defaults -Fragment $fragment.profiles.defaults

    $schemes = @()
    if ($settings.PSObject.Properties.Name -contains "schemes" -and $null -ne $settings.schemes) {
        $schemes = @($settings.schemes)
    }
    foreach ($newScheme in @($fragment.schemes)) {
        $schemes = @($schemes | Where-Object {
            -not (($_.PSObject.Properties.Name -contains "name") -and $_.name -eq $newScheme.name)
        })
        $schemes += $newScheme
    }
    Set-JsonProperty -InputObject $settings -Name "schemes" -Value $schemes

    $actions = @()
    if ($settings.PSObject.Properties.Name -contains "actions" -and $null -ne $settings.actions) {
        $actions = @($settings.actions)
    }
    foreach ($newAction in @($fragment.actions)) {
        $actions = @($actions | Where-Object {
            -not (($_.PSObject.Properties.Name -contains "keys") -and $_.keys -eq $newAction.keys)
        })
        $actions += $newAction
    }
    Set-JsonProperty -InputObject $settings -Name "actions" -Value $actions

    $mergedJson = $settings | ConvertTo-Json -Depth 100
    if ($mergedJson -eq $originalJson) {
        Write-Host "Windows Terminal settings already match the managed fragment."
        return
    }

    $backupPath = "$SettingsPath.$(Get-Date -Format yyyyMMddHHmmss).bak"
    Copy-Item -LiteralPath $SettingsPath -Destination $backupPath
    Set-Content -LiteralPath $SettingsPath -Value $mergedJson -Encoding UTF8

    Write-Host "Updated Windows Terminal settings."
    Write-Host "Backup written to $backupPath"
}

function Merge-TerminalSettingsFragment {
    if (-not $env:LOCALAPPDATA) {
        throw "LOCALAPPDATA is not set; cannot locate Windows Terminal settings."
    }

    $settingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    Merge-TerminalSettingsFile -SettingsPath $settingsPath -FragmentPath $TerminalFragment
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
        "AlwaysOnTop",
        "ColorPicker",
        "EnvironmentVariables",
        "FancyZones",
        "KeyboardManager",
        "PowerOCR",
        "PowerRename",
        "ShortcutGuide",
        "Workspaces"
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

if ($MyInvocation.InvocationName -eq ".") {
    return
}

if (-not ($ApplyPackages -or $ApplyPowerToys -or $InstallCommandPaletteFragment -or $InstallTerminalFragment -or $ExportPowerToysSchemas)) {
    Write-Host "Work laptop Windows profile checks"
    Write-Host "winget available: $(Test-CommandExists "winget")"
    Write-Host "PowerToys.DSC.exe: $(Get-PowerToysDscPath)"
    Write-Host ""
    Write-Host "WinGet 1.11 or later is required for DSC v3 configurations."
    Write-Host "Apply reviewed pieces explicitly:"
    Write-Host "  .\bootstrap.ps1 -ApplyPackages"
    Write-Host "  .\bootstrap.ps1 -ApplyPowerToys"
    Write-Host "  .\bootstrap.ps1 -InstallCommandPaletteFragment"
    Write-Host "  .\bootstrap.ps1 -InstallTerminalFragment"
    Write-Host "  .\bootstrap.ps1 -ExportPowerToysSchemas"
    exit 0
}

if ($ApplyPackages) {
    Invoke-WinGetConfigure -ConfigPath $PackageConfig
}

if ($ApplyPowerToys) {
    Invoke-WinGetConfigure -ConfigPath $PowerToysConfig
}

if ($InstallCommandPaletteFragment) {
    Merge-CommandPaletteSettingsFragment
}

if ($InstallTerminalFragment) {
    Merge-TerminalSettingsFragment
}

if ($ExportPowerToysSchemas) {
    Export-PowerToysSchemas
}
