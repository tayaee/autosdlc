$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
python (Join-Path $ScriptDir "log-cost.py") @args
