$GateName = "run-ruff"
$Report = Join-Path $env:TEMP "aacpd-$GateName-$PID.log"
$Verbose = $env:AACP_VERBOSE -eq "1"

if ($Verbose) {
    uv run ruff check --fix .
    exit $LASTEXITCODE
} else {
    uv run ruff check --fix . > $Report 2>&1
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
