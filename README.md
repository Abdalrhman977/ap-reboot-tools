# ap-reboot-tools

Small scripts for remotely rebooting access points and routers — handy when a
device hangs and you don't want to walk over and pull the plug.

| Script | Protocol | Runs on | Typical devices |
|---|---|---|---|
| `telnet-reboot.ps1` | Telnet (TCP 23) | Windows PowerShell 5.1+ / PowerShell 7 | APs and routers with a Telnet CLI |
| `hnap-reboot.sh` | HNAP1 over HTTP(S) | Linux, macOS, WSL, Git Bash | D-Link and other HNAP1-based routers/APs |

Both scripts can reboot one device or a whole list, and neither stores a password
in the file — you are prompted for it at run time.

---

## telnet-reboot.ps1

```powershell
# One device (prompts for the password)
.\telnet-reboot.ps1 -Target 192.168.1.10

# Several devices
.\telnet-reboot.ps1 -Target 192.168.1.10, 192.168.1.11 -Username admin

# From a file
.\telnet-reboot.ps1 -TargetFile .\devices.txt

# Dry run - show what would happen without connecting
.\telnet-reboot.ps1 -TargetFile .\devices.txt -WhatIf
```

| Parameter | Default | Description |
|---|---|---|
| `-Target` | | One or more IPs/hostnames |
| `-TargetFile` | | File with one host per line |
| `-Username` | `admin` | Login user |
| `-Password` | prompt | `SecureString`; prompted if not given |
| `-Port` | `23` | Telnet port |
| `-Command` | `reboot` | Command sent after login |
| `-TimeoutSeconds` | `5` | Connect timeout |

If Windows blocks the script, run it once with:

```powershell
powershell -ExecutionPolicy Bypass -File .\telnet-reboot.ps1 -Target 192.168.1.10
```

## hnap-reboot.sh

```bash
chmod +x hnap-reboot.sh

# One device (prompts for the password)
./hnap-reboot.sh 192.168.0.1

# From a file, different username
./hnap-reboot.sh -u admin -f devices.txt

# Non-interactive (e.g. cron) - password from an environment variable
HNAP_PASSWORD='...' ./hnap-reboot.sh 192.168.0.1
```

| Option | Description |
|---|---|
| `-u USER` | Login user (default `admin`) |
| `-f FILE` | File with one host per line |
| `-s` | Use `http` instead of `https` |

Exit code = number of devices that failed (0 = all OK).

How it works: the script requests a login challenge, derives the private key with
HMAC-MD5 (`PublicKey + password` over the challenge), logs in, then signs the
`Reboot` SOAP action with an `HNAP_AUTH` header.

## Device list format

See [`devices.example.txt`](devices.example.txt). Copy it to `devices.txt`
(which is git-ignored) and put your own addresses in it.

---

## Security notes

- **Telnet is unencrypted.** The password travels in plain text. Only use it on a
  trusted management network, and prefer SSH where the device supports it.
- `hnap-reboot.sh` uses `curl -k` because these devices almost always have
  self-signed certificates.
- Never commit real passwords or your `devices.txt`.
- Only use these tools on equipment you own or are authorised to manage.

## License

MIT
