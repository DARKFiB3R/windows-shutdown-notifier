# PowerShell Shutdown Notification Setup Guide

This guide will help you set up a **Windows Toast Notification system** that shows you the reason for your computer's last shutdown or restart when you log in.

<img width="396" height="463" alt="Photos_2025-09-15_07-51-25" src="https://github.com/user-attachments/assets/05bc347a-e83b-4113-97be-88d7e9ed5db9" />

## What You'll Get

- 🔔 **Modern toast notifications** that appear ~20 seconds after login
- 📝 **Detailed shutdown reasons** (user shutdown, restart, crash, etc.)
- 📋 **Persistent notifications** in Windows Notification Center
- 📄 **Automatic log file** with newest events first
- ⚡ **Fast startup** - no delay waiting for Windows to fully load

## Requirements

- **Windows 10 or Windows 11**
- **PowerShell** (pre-installed on Windows)
- **Administrator privileges** (for installation only)

---

## Step-by-Step Installation

### Step 1: Download the Script

Copy the PowerShell script below and save it as **`ShutdownNotifier.ps1`**

**Important:** Make sure the filename ends with `.ps1` and save it somewhere easy to find (like your Desktop or Documents folder).

```powershell
# Windows Shutdown Notification System
# Shows toast notifications with shutdown/restart reasons

param(
    [switch]$Install,      # Install as startup service
    [switch]$Uninstall,   # Remove startup service
    [switch]$Monitor       # Run test mode
)

function Show-ShutdownToast {
    param([string]$Title, [string]$EventType, [string]$EventTime, [string]$Reason)
    
    # Log to Documents folder (newest entries first)
    $LogPath = "$env:USERPROFILE\Documents\ShutdownNotifier.log"
    $LogEntry = "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') - $Title`n$EventType at $EventTime - $Reason`n" + ("-" * 60)
    
    try {
        $ExistingContent = if (Test-Path $LogPath) { Get-Content $LogPath -Raw -ErrorAction SilentlyContinue } else { "" }
        $NewContent = $LogEntry + "`n" + $ExistingContent
        Set-Content -Path $LogPath -Value $NewContent -ErrorAction SilentlyContinue
    } catch {
        try { Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue } catch { }
    }
    
    # Show toast notification
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        
        $Message = "$EventType at $EventTime - $Reason"
        
        $ToastXml = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$Message</text>
        </binding>
    </visual>
    <actions>
        <action content="View Log" arguments="$LogPath" activationType="protocol"/>
        <action content="Dismiss" arguments="dismiss"/>
    </actions>
</toast>
"@
        
        $XmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $XmlDoc.LoadXml($ToastXml)
        $Toast = [Windows.UI.Notifications.ToastNotification]::new($XmlDoc)
        $Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell.ShutdownNotifier")
        $Notifier.Show($Toast)
        
        Write-Host "✓ Toast notification sent: $Title" -ForegroundColor Green
        return $true
        
    } catch {
        # Fallback to balloon tip if toast fails
        Write-Host "Toast failed, using balloon notification: $($_.Exception.Message)" -ForegroundColor Yellow
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $notification = New-Object System.Windows.Forms.NotifyIcon
            $notification.Icon = [System.Drawing.SystemIcons]::Information
            $notification.BalloonTipTitle = $Title
            $notification.BalloonTipText = "$EventType at $EventTime - $Reason"
            $notification.Visible = $True
            $notification.ShowBalloonTip(15000)
            Start-Sleep -Seconds 2
            $notification.Dispose()
            Write-Host "✓ Balloon notification sent as fallback" -ForegroundColor Green
        } catch {
            Write-Host "✗ All notification methods failed" -ForegroundColor Red
        }
        return $false
    }
}

function Get-LastShutdownEvent {
    try {
        $Event = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ID = 1074, 6006, 6008
        } -MaxEvents 1 -ErrorAction SilentlyContinue | Sort-Object TimeCreated -Descending | Select-Object -First 1
        
        if ($Event) {
            $EventTime = $Event.TimeCreated.ToString("yyyy/MM/dd HH:mm:ss")
            $EventID = $Event.Id
            
            switch ($EventID) {
                1074 {
                    $EventMessage = $Event.Message
                    $EventType = if ($EventMessage -match "restart") { "Planned Restart" } else { "Planned Shutdown" }
                    $Reason = if ($EventMessage -match "Reason: (.+?)(\r|\n|$)") { $matches[1].Trim() } else { "User or system initiated" }
                }
                6006 {
                    $EventType = "Clean Shutdown"
                    $Reason = "Normal system shutdown"
                }
                6008 {
                    $EventType = "Unexpected Shutdown"
                    $Reason = "System crashed or lost power"
                }
            }
            
            return @{
                Title = "Last System Event: $EventType"
                EventType = $EventType
                EventTime = $EventTime
                Reason = $Reason
                Time = $Event.TimeCreated
            }
        }
        return $null
    } catch {
        Write-Host "Error getting shutdown events: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Install-ShutdownNotifier {
    Write-Host "Installing Windows Shutdown Notifier..." -ForegroundColor Yellow
    
    $ScriptPath = $PSCommandPath
    $TaskName = "WindowsShutdownNotifier"
    
    $TaskXML = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Windows Shutdown Notifier - Shows notifications for shutdown/restart events</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT15S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-WindowStyle Hidden -ExecutionPolicy Bypass -NonInteractive -File "$ScriptPath" -Monitor</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    
    try {
        Register-ScheduledTask -TaskName $TaskName -Xml $TaskXML -Force
        Write-Host "✓ Windows Shutdown Notifier installed successfully!" -ForegroundColor Green
        Write-Host "  • Starts automatically 15 seconds after login" -ForegroundColor Gray
        Write-Host "  • Shows notifications for all shutdown/restart events" -ForegroundColor Gray
        Write-Host "  • Logs events to: $env:USERPROFILE\Documents\ShutdownNotifier.log" -ForegroundColor Gray
    } catch {
        Write-Host "✗ Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Make sure you're running PowerShell as Administrator" -ForegroundColor Yellow
    }
}

function Uninstall-ShutdownNotifier {
    Write-Host "Removing Windows Shutdown Notifier..." -ForegroundColor Yellow
    try {
        Unregister-ScheduledTask -TaskName "WindowsShutdownNotifier" -Confirm:$false
        Write-Host "✓ Windows Shutdown Notifier removed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "✗ Removal failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Start-NotificationMonitoring {
    Start-Sleep -Seconds 5  # Brief delay for system readiness
    
    $LastEvent = Get-LastShutdownEvent
    if ($LastEvent) {
        Show-ShutdownToast -Title $LastEvent.Title -EventType $LastEvent.EventType -EventTime $LastEvent.EventTime -Reason $LastEvent.Reason
        $LastEventTime = $LastEvent.Time
    } else {
        $LastEventTime = Get-Date
        # Log startup without showing notification
        $LogPath = "$env:USERPROFILE\Documents\ShutdownNotifier.log"
        try {
            $LogEntry = "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') - Notifier Started (No recent events found)`n" + ("-" * 60)
            $ExistingContent = if (Test-Path $LogPath) { Get-Content $LogPath -Raw -ErrorAction SilentlyContinue } else { "" }
            Set-Content -Path $LogPath -Value ($LogEntry + "`n" + $ExistingContent) -ErrorAction SilentlyContinue
        } catch { }
    }
    
    # Continue monitoring for new events
    while ($true) {
        Start-Sleep -Seconds 45
        $CurrentEvent = Get-LastShutdownEvent
        if ($CurrentEvent -and $CurrentEvent.Time -gt $LastEventTime) {
            $LastEventTime = $CurrentEvent.Time
            Show-ShutdownToast -Title $CurrentEvent.Title -EventType $CurrentEvent.EventType -EventTime $CurrentEvent.EventTime -Reason $CurrentEvent.Reason
        }
    }
}

# Main execution
if ($Install) {
    Install-ShutdownNotifier
} elseif ($Uninstall) {
    Uninstall-ShutdownNotifier
} elseif ($Monitor) {
    if ([Environment]::UserInteractive -and -not [Environment]::GetCommandLineArgs().Contains("-NonInteractive")) {
        Write-Host "=== Windows Shutdown Notifier Test ===" -ForegroundColor Cyan
        Write-Host "Testing notification system..." -ForegroundColor Yellow
        
        $LastEvent = Get-LastShutdownEvent
        if ($LastEvent) {
            Show-ShutdownToast -Title $LastEvent.Title -EventType $LastEvent.EventType -EventTime $LastEvent.EventTime -Reason $LastEvent.Reason
            Write-Host "✓ Test notification sent!" -ForegroundColor Green
        } else {
            Write-Host "⚠ No recent shutdown events found to display" -ForegroundColor Yellow
        }
        
        Write-Host "Log file: $env:USERPROFILE\Documents\ShutdownNotifier.log" -ForegroundColor Cyan
    } else {
        Start-NotificationMonitoring
    }
} else {
    Write-Host "=== Windows Shutdown Notifier ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Shows toast notifications with shutdown/restart reasons" -ForegroundColor White
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "  .\ShutdownNotifier.ps1 -Monitor    # Test notifications" -ForegroundColor Blue
    Write-Host "  .\ShutdownNotifier.ps1 -Install    # Install as startup service" -ForegroundColor Green  
    Write-Host "  .\ShutdownNotifier.ps1 -Uninstall  # Remove startup service" -ForegroundColor Red
    Write-Host ""
    Write-Host "FEATURES:" -ForegroundColor Yellow
    Write-Host "• Fast startup (15 seconds after login)" -ForegroundColor Gray
    Write-Host "• Modern toast notifications with action buttons" -ForegroundColor Gray
    Write-Host "• Automatic logging to Documents folder" -ForegroundColor Gray
    Write-Host "• Shows detailed shutdown/restart reasons" -ForegroundColor Gray
    Write-Host "• Continues monitoring for new events" -ForegroundColor Gray
}
```

### Step 2: Open PowerShell

1. **Press `Windows Key + R`**
2. **Type:** `powershell`
3. **Press Enter**

A blue PowerShell window will open.

### Step 3: Navigate to Your Script

Use the `cd` command to go to where you saved the script. For example:

```powershell
# If you saved it on your Desktop:
cd "$env:USERPROFILE\Desktop"

# If you saved it in Documents:
cd "$env:USERPROFILE\Documents"

# If you saved it somewhere else, replace with your path:
cd "C:\Path\To\Your\Script"
```

### Step 4: Allow Script Execution

PowerShell blocks scripts by default for security. Run this command:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

**When prompted**, you'll see something like:
```
Execution Policy Change
The execution policy helps protect you from scripts that you do not trust...
Do you want to change the execution policy?
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"):
```

**Type `A` and press Enter** (this means "Yes to All" and will allow the script to run).

### Step 5: Test the Script

Run this command to test if everything works:

```powershell
.\ShutdownNotifier.ps1 -Monitor
```

You should see:
- ✅ Console messages confirming the test
- 🔔 A toast notification showing your last shutdown event
- 📄 A log file created in your Documents folder

### Step 6: Install the Notifier

If the test worked, install it to run automatically:

```powershell
.\ShutdownNotifier.ps1 -Install
```

You should see a success message. The notifier is now installed and will start automatically every time you log in!

---

## How It Works

- **After Login:** The notifier starts automatically 15 seconds after you log in
- **Notification:** A toast notification appears showing your last shutdown/restart reason
- **Log File:** All events are logged to `Documents\ShutdownNotifier.log` (newest first)
- **Monitoring:** Continues running in the background to catch new shutdown events

## Notification Examples

You might see notifications like:
- "**Last System Event: Clean Shutdown** - Clean Shutdown at 2025/09/14 18:31:04 - Normal system shutdown"
- "**Last System Event: Planned Restart** - Planned Restart at 2025/09/14 12:15:32 - User or system initiated"
- "**Last System Event: Unexpected Shutdown** - Unexpected Shutdown at 2025/09/14 08:42:18 - System crashed or lost power"

## Managing the Notifier

### View Log File
```powershell
# Open the log file in Notepad
notepad "$env:USERPROFILE\Documents\ShutdownNotifier.log"

# Or view in PowerShell
Get-Content "$env:USERPROFILE\Documents\ShutdownNotifier.log" -Head 10
```

### Test Again
```powershell
.\ShutdownNotifier.ps1 -Monitor
```

### Uninstall
```powershell
.\ShutdownNotifier.ps1 -Uninstall
```

---

## Troubleshooting

### "Execution Policy" Error
Make sure you ran:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```
And chose `A` for "Yes to All"

### "Cannot find path" Error
Make sure you're in the correct folder where you saved `ShutdownNotifier.ps1`:
```powershell
# List files in current directory
ls *.ps1

# If you don't see ShutdownNotifier.ps1, navigate to correct folder
cd "C:\Correct\Path\To\Script"
```

### No Toast Notifications
If you only see balloon tips instead of modern toast notifications:
1. Check **Windows Settings** > **System** > **Notifications & actions**
2. Make sure **"Get notifications from apps and other senders"** is ON
3. Look for **"PowerShell.ShutdownNotifier"** in the list and enable it

### Installation Fails
Make sure you're running PowerShell **as Administrator**:
1. Right-click **Start Menu**
2. Click **"Windows PowerShell (Admin)"** or **"Terminal (Admin)"**
3. Navigate to your script and try installing again

---

## System Requirements

- **Windows 10 version 1903 or later**
- **Windows 11 (any version)**
- **PowerShell 5.1 or later** (pre-installed on Windows)
- **Toast notifications enabled** in Windows Settings

---

## Privacy & Security

- ✅ **No internet connection required** - works completely offline
- ✅ **No data sent anywhere** - everything stays on your computer
- ✅ **Open source** - you can see exactly what the code does
- ✅ **Minimal permissions** - doesn't require administrator rights to run
- ✅ **Safe to use** - only reads Windows event logs and shows notifications

---

## Credits

This guide and script were created to help Windows users understand why their computer shut down or restarted. Feel free to share this guide with others who might find it useful!

**Version:** 1.0  
**Compatible with:** Windows 10/11  

**Last Updated:** September 2025
