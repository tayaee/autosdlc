$GateName = "run-pyright"
$Report = Join-Path $env:TEMP "aacpd-$GateName-$PID.log"
$Verbose = $env:AACP_VERBOSE -eq "1"

if ($Verbose) {
    if (Test-Path src) { uv run pyright src } else { uv run pyright . }
    exit $LASTEXITCODE
} else {
    if (Test-Path src) { uv run pyright src } else { uv run pyright . } > $Report 2>&1
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -eq 0) {
        Remove-Item -Force $Report -ErrorAction SilentlyContinue
        exit 0
    } else {
        [Console]::Error.WriteLine("ERROR: $GateName failed with exit code $ExitCode.")
        [Console]::Error.WriteLine("Full log saved to: $Report")
        [Console]::Error.WriteLine("--- Last 60 lines of $Report ---")
        Get-Content -Tail 60 $Report | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit $ExitCode
    }
}
