[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$SkipUpload,
    [switch]$NoDialogs,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PipelineArguments
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $RepoRoot "config.local.json"
$NcodeInstallUrl = "https://flyzipline.atlassian.net/wiki/spaces/REL/pages/1928953995/ReliaSoft+and+nCode+Installation+and+Setup"

function Show-Message {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Title = "Instrument Flight Test Processing",
        [ValidateSet("Info", "Error")][string]$Kind = "Info"
    )

    Write-Host ""
    Write-Host $Text -ForegroundColor $(if ($Kind -eq "Error") { "Red" } else { "Green" })
    if ($NoDialogs) {
        return
    }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $icon = if ($Kind -eq "Error") { "Error" } else { "Information" }
        [System.Windows.MessageBox]::Show($Text, $Title, "OK", $icon) | Out-Null
    }
    catch {
        # The console message remains available if the Windows dialog cannot be loaded.
    }
}

function Stop-Missing {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$OpenFolder,
        [string]$OpenUrl
    )

    Show-Message -Text $Text -Kind Error
    if (-not $NoDialogs -and $OpenFolder -and (Test-Path -LiteralPath $OpenFolder)) {
        Start-Process explorer.exe -ArgumentList ('"' + $OpenFolder + '"')
    }
    if (-not $NoDialogs -and $OpenUrl) {
        Start-Process $OpenUrl
    }
    exit 1
}

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Default,
        [object]$Config
    )

    $environmentName = "IFT_$($Key.ToUpperInvariant())"
    $value = [Environment]::GetEnvironmentVariable($environmentName)
    if (-not $value -and $Config -and $Config.PSObject.Properties.Name -contains $Key) {
        $value = [string]$Config.$Key
    }
    if (-not $value) {
        $value = $Default
    }
    return [Environment]::ExpandEnvironmentVariables($value)
}

Write-Host "Instrument Flight Test Processing - one-click launcher" -ForegroundColor Cyan
Write-Host "Repository: $RepoRoot"

$pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $pythonCommand) {
    Stop-Missing "Python is missing.`n`nInstall Python 3, select 'Add Python to PATH', and then run START-PROCESSING.cmd again."
}
$Python = $pythonCommand.Source

$awsCommand = Get-Command aws.exe -ErrorAction SilentlyContinue
if (-not $awsCommand) {
    $awsCommand = Get-Command aws -ErrorAction SilentlyContinue
}
if (-not $awsCommand) {
    Stop-Missing "AWS CLI is missing.`n`nInstall AWS CLI v2 and then run START-PROCESSING.cmd again."
}
$Aws = $awsCommand.Source

$config = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
    }
    catch {
        Stop-Missing "The configuration file is not valid JSON:`n$ConfigPath`n`n$($_.Exception.Message)"
    }
}

$baseDir = Resolve-ConfiguredPath -Key "base_dir" -Default $RepoRoot -Config $config
$processingDir = Resolve-ConfiguredPath -Key "processing_dir" -Default (Join-Path $baseDir "Processing data") -Config $config
$csvDir = Resolve-ConfiguredPath -Key "csv_dir" -Default (Join-Path $processingDir "csv") -Config $config
$workflowDir = Resolve-ConfiguredPath -Key "ncode_workflow_dir" -Default (Join-Path $baseDir "ncode_workflows") -Config $config
$asciiTranslate = Resolve-ConfiguredPath -Key "ascii_translate_exe" -Default "C:\Program Files\nCode\nCode 2025.1 64-bit\GlyphWorks\bin\asciitranslate.exe" -Config $config
$flowproc = Resolve-ConfiguredPath -Key "flowproc_exe" -Default "C:\Program Files\nCode\nCode 2025.1 64-bit\GlyphWorks\bin\flowproc.exe" -Config $config

$missingNcode = @()
if (-not (Test-Path -LiteralPath $asciiTranslate -PathType Leaf)) { $missingNcode += $asciiTranslate }
if (-not (Test-Path -LiteralPath $flowproc -PathType Leaf)) { $missingNcode += $flowproc }
if ($missingNcode.Count -gt 0) {
    $paths = $missingNcode -join "`n"
    Stop-Missing "nCode 2025.1 is missing, or it is installed in a different location.`n`nMissing executable(s):`n$paths`n`nDownload and install nCode using the Zipline setup page:`n$NcodeInstallUrl`n`nThe page will open after you close this message.`n`nIf nCode is already installed elsewhere, update config.local.json." -OpenUrl $NcodeInstallUrl
}

$requiredWorkflows = @(
    (Join-Path $workflowDir "0_FlightPhaseSplit.flo"),
    (Join-Path $workflowDir "4_FDS_SRS.flo")
)
$missingWorkflows = @($requiredWorkflows | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missingWorkflows.Count -gt 0) {
    $paths = $missingWorkflows -join "`n"
    Stop-Missing "Required nCode workflow file(s) are missing:`n`n$paths`n`nRestore them from GitHub or the team Google Drive, then run this launcher again." -OpenFolder $workflowDir
}

Write-Host "Preparing processing folders..."
& $Python (Join-Path $RepoRoot "setup_project.py")
if ($LASTEXITCODE -ne 0) {
    Stop-Missing "The processing folders could not be prepared. Review the console output for details."
}

Write-Host "Checking Python packages..."
$previousErrorPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Python -c "import boto3, gdown, pyperclip, pywinauto" 2>&1 | Out-Null
$packageCheckExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorPreference
if ($packageCheckExitCode -ne 0) {
    Write-Host "Installing required Python packages..." -ForegroundColor Yellow
    & $Python -m pip install -r (Join-Path $RepoRoot "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        Stop-Missing "Required Python packages could not be installed.`n`nCheck the internet connection and run:`npython -m pip install -r `"$RepoRoot\requirements.txt`""
    }
}

$csvFiles = @(Get-ChildItem -LiteralPath $csvDir -Filter "*.csv" -File -ErrorAction SilentlyContinue)
if ($csvFiles.Count -eq 0) {
    Stop-Missing "No input CSV files were found.`n`nPlace the flight CSV file(s) here:`n$csvDir`n`nThe folder will open after you close this message." -OpenFolder $csvDir
}

Write-Host ""
Write-Host "Prerequisite check passed:" -ForegroundColor Green
Write-Host "  Python: $Python"
Write-Host "  AWS CLI: $Aws"
Write-Host "  nCode flow processor: $flowproc"
Write-Host "  Workflow folder: $workflowDir"
Write-Host "  Input CSV files: $($csvFiles.Count)"

if ($CheckOnly) {
    Show-Message "All required software, workflow files, packages, and CSV inputs are ready."
    exit 0
}

Write-Host ""
Write-Host "Starting the nCode processing pipeline..." -ForegroundColor Cyan
$pipelineScript = Join-Path $RepoRoot "code\final_code.py"
& $Python $pipelineScript @PipelineArguments
if ($LASTEXITCODE -ne 0) {
    Stop-Missing "The nCode processing pipeline stopped with exit code $LASTEXITCODE.`n`nResults were not uploaded. Review the console output for the error."
}

if (-not $SkipUpload) {
    $profile = if ($config -and $config.preferred_aws_profile) { [string]$config.preferred_aws_profile } else { "ncode-sso" }
    Write-Host ""
    Write-Host "Checking AWS login for profile $profile..." -ForegroundColor Cyan
    & $Aws sts get-caller-identity --profile $profile *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "AWS sign-in is required. A browser window may open." -ForegroundColor Yellow
        & $Aws sso login --profile $profile
        if ($LASTEXITCODE -ne 0) {
            Stop-Missing "AWS sign-in failed for profile '$profile'.`n`nProcessing completed, but the results were not uploaded."
        }
    }

    Write-Host "Uploading completed results to AWS..." -ForegroundColor Cyan
    & $Python (Join-Path $RepoRoot "code\upload_to_aws.py") --profile $profile
    if ($LASTEXITCODE -ne 0) {
        Stop-Missing "Processing completed, but the AWS upload stopped with exit code $LASTEXITCODE.`n`nReview the console output for the error."
    }
}

$completion = if ($SkipUpload) {
    "nCode processing finished successfully. AWS upload was skipped."
}
else {
    "nCode processing and the AWS upload finished successfully."
}
Show-Message $completion
exit 0
