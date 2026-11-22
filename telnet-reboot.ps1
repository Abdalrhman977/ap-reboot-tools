<#
.SYNOPSIS
    Reboots one or more access points / routers over Telnet.

.DESCRIPTION
    Connects to each device on the Telnet port, logs in with the given
    username and password, and sends the reboot command.

    WARNING: Telnet sends the password in plain text. Only use this on a
    network you trust.

.PARAMETER Target
    One or more IP addresses or hostnames.

.PARAMETER TargetFile
    A text file with one IP/hostname per line (lines starting with # are ignored).

.PARAMETER Username
    Login username. Default: admin

.PARAMETER Password
    Login password as a SecureString. If omitted you are prompted for it.

.PARAMETER Port
    Telnet port. Default: 23

.PARAMETER Command
    The command to send after login. Default: reboot

.EXAMPLE
    .\telnet-reboot.ps1 -Target 192.168.1.10

.EXAMPLE
    .\telnet-reboot.ps1 -TargetFile .\devices.txt -Username admin
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Target,
    [string]$TargetFile,
    [string]$Username = 'admin',
    [SecureString]$Password,
    [int]$Port = 23,
    [string]$Command = 'reboot',
    [int]$TimeoutSeconds = 5
)

$ErrorActionPreference = 'Stop'

# Build the list of devices
$devices = @()
if ($Target) { $devices += $Target }
if ($TargetFile) {
    if (-not (Test-Path $TargetFile)) { throw "Target file not found: $TargetFile" }
    $devices += Get-Content $TargetFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}
if (-not $devices) { throw 'Give at least one device with -Target or -TargetFile.' }

if (-not $Password) { $Password = Read-Host -AsSecureString "Password for $Username" }
$plainPassword = [System.Net.NetworkCredential]::new('', $Password).Password

function Read-Available([System.IO.Stream]$Stream) {
    $buffer = New-Object byte[] 4096
    $text = ''
    while ($Stream.DataAvailable) {
        $n = $Stream.Read($buffer, 0, $buffer.Length)
        $text += [System.Text.Encoding]::ASCII.GetString($buffer, 0, $n)
    }
    return $text
}

$results = foreach ($device in $devices) {
    if (-not $PSCmdlet.ShouldProcess($device, "Send '$Command' over Telnet")) { continue }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect($device, $Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            throw "Connection timed out after $TimeoutSeconds s"
        }
        $client.EndConnect($connect)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        Start-Sleep -Seconds 1; $null = Read-Available $stream
        $writer.WriteLine($Username)
        Start-Sleep -Seconds 1; $null = Read-Available $stream
        $writer.WriteLine($plainPassword)
        Start-Sleep -Seconds 1
        $afterLogin = Read-Available $stream
        if ($afterLogin -match '(?i)incorrect|failed|denied|invalid') {
            throw 'Login rejected'
        }
        $writer.WriteLine($Command)
        Start-Sleep -Seconds 2

        Write-Host "[OK]   $device - '$Command' sent" -ForegroundColor Green
        [pscustomobject]@{ Device = $device; Status = 'Sent' }
    }
    catch {
        Write-Host "[FAIL] $device - $($_.Exception.Message)" -ForegroundColor Red
        [pscustomobject]@{ Device = $device; Status = "Failed: $($_.Exception.Message)" }
    }
    finally {
        $client.Close()
    }
}

$plainPassword = $null
$results
