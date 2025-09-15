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