if (-not $env:WINDIR) { throw "Open AutoClicker requires Windows." }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class NativeInput {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point pt);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);

    struct Point { public int X, Y; }
    struct Rect { public int Left, Top, Right, Bottom; }

    static readonly object Gate = new object();
    static Thread Worker;
    static volatile bool RunningFlag;
    static bool TargetIsMouse = true;
    static int TargetVk = 1, TargetButton = 1, IntervalMs = 100;
    static IntPtr WindowHandle = IntPtr.Zero;
    static DateTime EndAt = DateTime.MinValue, LastFire = DateTime.MinValue, SuppressUntil = DateTime.MinValue;

    public static bool IsRunning { get { return RunningFlag; } }
    public static bool IsSuppressed { get { return RunningFlag && DateTime.UtcNow < SuppressUntil; } }
    public static bool CursorIsInWindow { get { return CursorInWindow(WindowHandle); } }
    public static int RemainingSeconds {
        get { return RunningFlag ? Math.Max(0, (int)Math.Ceiling((EndAt - DateTime.UtcNow).TotalSeconds)) : 0; }
    }

    public static void SetTarget(bool isMouse, int vk, int button) {
        lock (Gate) { TargetIsMouse = isMouse; TargetVk = vk; TargetButton = button; }
    }

    public static void SetInterval(int intervalMs) {
        lock (Gate) { IntervalMs = Math.Max(10, Math.Min(5000, intervalMs)); }
    }

    public static void Start(int minutes, int intervalMs, IntPtr hwnd) {
        lock (Gate) {
            SetInterval(intervalMs);
            WindowHandle = hwnd;
            EndAt = DateTime.UtcNow.AddMinutes(Math.Max(1, Math.Min(60, minutes)));
            LastFire = DateTime.UtcNow;
            SuppressUntil = DateTime.UtcNow.AddMilliseconds(650);
            RunningFlag = true;
            if (Worker == null || !Worker.IsAlive) {
                Worker = new Thread(Loop);
                Worker.IsBackground = true;
                Worker.Name = "OpenAutoClickerLoop";
                Worker.Start();
            }
        }
    }

    public static void Stop() { RunningFlag = false; }

    static void Loop() {
        while (RunningFlag) {
            bool isMouse;
            int vk, button, interval;
            IntPtr hwnd;
            DateTime endAt, lastFire, suppressUntil;

            lock (Gate) {
                isMouse = TargetIsMouse; vk = TargetVk; button = TargetButton; interval = IntervalMs;
                hwnd = WindowHandle; endAt = EndAt; lastFire = LastFire; suppressUntil = SuppressUntil;
            }

            DateTime now = DateTime.UtcNow;
            if (now >= endAt) { RunningFlag = false; break; }

            bool pausedForWindow = isMouse && CursorInWindow(hwnd);
            if (now >= suppressUntil && !pausedForWindow && (now - lastFire).TotalMilliseconds >= interval) {
                Fire(isMouse, vk, button);
                lock (Gate) { LastFire = now; }
            }
            Thread.Sleep(5);
        }
    }

    static bool CursorInWindow(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return false;
        Point pt; Rect rc;
        if (!GetCursorPos(out pt) || !GetWindowRect(hwnd, out rc)) return false;
        return pt.X >= rc.Left && pt.X <= rc.Right && pt.Y >= rc.Top && pt.Y <= rc.Bottom;
    }

    static void Fire(bool isMouse, int vk, int button) {
        if (!isMouse) {
            keybd_event((byte)vk, 0, 0, UIntPtr.Zero);
            keybd_event((byte)vk, 0, 0x0002, UIntPtr.Zero);
            return;
        }

        uint down = 0x0002, up = 0x0004, data = 0;
        if (button == 2) { down = 0x0008; up = 0x0010; }
        else if (button == 3) { down = 0x0020; up = 0x0040; }
        else if (button == 4) { down = 0x0080; up = 0x0100; data = 1; }
        else if (button == 5) { down = 0x0080; up = 0x0100; data = 2; }
        mouse_event(down, 0, 0, data, UIntPtr.Zero);
        mouse_event(up, 0, 0, data, UIntPtr.Zero);
    }
}
"@

function New-Input($Name, $Vk, $IsMouse = $false, $Button = 0) {
    [pscustomobject]@{ Name = $Name; Vk = [int]$Vk; IsMouse = $IsMouse; Button = [int]$Button }
}

$mouseInputs = @(
    (New-Input "Mouse1" 0x01 $true 1),
    (New-Input "Mouse2" 0x02 $true 2),
    (New-Input "Mouse3" 0x04 $true 3),
    (New-Input "Mouse4" 0x05 $true 4),
    (New-Input "Mouse5" 0x06 $true 5)
)

$theme = @{
    Black  = [Drawing.Color]::Black
    White  = [Drawing.Color]::White
    Paper  = [Drawing.Color]::FromArgb(250, 250, 250)
    Soft   = [Drawing.Color]::FromArgb(238, 238, 238)
    Muted  = [Drawing.Color]::FromArgb(86, 86, 86)
    Border = [Drawing.Color]::FromArgb(32, 32, 32)
}

$state = @{
    Target       = $mouseInputs[0]
    Toggle       = New-Input "F6" ([Windows.Forms.Keys]::F6)
    Capture      = $null
    CaptureAfter = [datetime]::MinValue
    LastToggle   = $false
}

function Test-Down($vk) {
    ([NativeInput]::GetAsyncKeyState([int]$vk) -band 0x8000) -ne 0
}

function Get-PressedInput {
    if ([datetime]::Now -lt $state.CaptureAfter) { return $null }
    foreach ($candidate in $mouseInputs) {
        if (Test-Down $candidate.Vk) { return $candidate }
    }
    foreach ($key in [Enum]::GetValues([Windows.Forms.Keys])) {
        $vk = [int]$key
        if ($vk -gt 0 -and $vk -lt 255 -and (Test-Down $vk)) { return New-Input $key.ToString() $vk }
    }
}

function Format-Remaining($seconds) {
    if ($seconds -lt 60) { return "$seconds seconds" }
    $minutes = [int][Math]::Floor($seconds / 60)
    $seconds = $seconds % 60
    if ($seconds) { "$minutes min $seconds sec" } else { "$minutes minutes" }
}

function Set-EngineTarget {
    [NativeInput]::SetTarget($state.Target.IsMouse, $state.Target.Vk, $state.Target.Button)
}

function Start-Clicking {
    if ($state.Capture) { return }
    Set-EngineTarget
    [NativeInput]::Start([int]$duration.Value, [int]$interval.Value, $form.Handle)
    $state.LastToggle = Test-Down $state.Toggle.Vk
    Refresh-Ui
}

function Stop-Clicking {
    [NativeInput]::Stop()
    Refresh-Ui
}

function Toggle-Clicking {
    if ([NativeInput]::IsRunning) { Stop-Clicking } else { Start-Clicking }
}

function Set-Capture($mode) {
    $state.Capture = $mode
    $state.CaptureAfter = [datetime]::Now.AddMilliseconds(300)
    Refresh-Ui
}

function Refresh-Ui {
    $targetValue.Text = $state.Target.Name
    $toggleValue.Text = $state.Toggle.Name
    $durationValue.Text = "$($duration.Value) minutes"
    $toggleButton.Text = if ([NativeInput]::IsRunning) { "Stop" } else { "Start" }

    if ($state.Capture) {
        $status.Text = if ($state.Capture -eq "target") { "Press the input to repeat" } else { "Press the toggle input" }
    }
    elseif (-not [NativeInput]::IsRunning) {
        $status.Text = "Stopped"
    }
    elseif ([NativeInput]::IsSuppressed) {
        $status.Text = "Starting - move cursor to target"
    }
    elseif ($state.Target.IsMouse -and [NativeInput]::CursorIsInWindow) {
        $status.Text = "Paused - cursor is over app window"
    }
    else {
        $status.Text = "Running - $(Format-Remaining ([NativeInput]::RemainingSeconds)) left"
    }
}

function Add-Text($parent, $text, $x, $y, $w, $h = 24, $size = 10, $bold = $false, $align = "MiddleLeft") {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object Drawing.Point($x, $y)
    $label.Size = New-Object Drawing.Size($w, $h)
    $label.BackColor = $theme.White
    $label.ForeColor = $theme.Black
    $label.TextAlign = $align
    $style = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $label.Font = New-Object Drawing.Font("Segoe UI", $size, $style)
    $parent.Controls.Add($label)
    $label
}

function Add-Button($parent, $text, $x, $y, $w, $h, $handler) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object Drawing.Point($x, $y)
    $button.Size = New-Object Drawing.Size($w, $h)
    $button.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
    $button.BackColor = $theme.White
    $button.ForeColor = $theme.Black
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderColor = $theme.Border
    $button.FlatAppearance.MouseDownBackColor = [Drawing.Color]::Gainsboro
    $button.FlatAppearance.MouseOverBackColor = $theme.Soft
    $button.UseVisualStyleBackColor = $false
    $button.Add_Click($handler)
    $parent.Controls.Add($button)
    $button
}

function Add-Section($title, $x, $y, $w, $h) {
    $panel = New-Object Windows.Forms.Panel
    $panel.Location = New-Object Drawing.Point($x, $y)
    $panel.Size = New-Object Drawing.Size($w, $h)
    $panel.BackColor = $theme.White
    $panel.BorderStyle = "FixedSingle"
    $form.Controls.Add($panel)
    Add-Text $panel $title 18 10 ($w - 36) 24 10 $true | Out-Null
    $panel
}

$form = New-Object Windows.Forms.Form
$form.Text = "Open AutoClicker"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.ClientSize = New-Object Drawing.Size(520, 610)
$form.Font = New-Object Drawing.Font("Segoe UI", 10)
$form.BackColor = $theme.Paper
$form.ForeColor = $theme.Black

Add-Text $form "Open AutoClicker" 40 24 440 40 20 $true "MiddleCenter" | Out-Null
$status = Add-Text $form "" 40 78 440 38 10 $false "MiddleCenter"
$status.BorderStyle = "FixedSingle"

$targetSection = Add-Section "Target Input" 40 138 440 90
Add-Text $targetSection "Input" 22 46 80 24 9 | Out-Null
$targetValue = Add-Text $targetSection "" 112 46 150 24 11 $true
Add-Button $targetSection "Bind Input" 282 39 132 34 { Set-Capture "target" } | Out-Null

$toggleSection = Add-Section "Toggle Hotkey" 40 246 440 90
Add-Text $toggleSection "Hotkey" 22 46 80 24 9 | Out-Null
$toggleValue = Add-Text $toggleSection "" 112 46 150 24 11 $true
Add-Button $toggleSection "Bind Toggle" 282 39 132 34 { Set-Capture "toggle" } | Out-Null

$timingSection = Add-Section "Timing" 40 354 440 130
Add-Text $timingSection "Duration" 22 45 90 24 9 | Out-Null
$durationValue = Add-Text $timingSection "" 112 45 140 24 11 $true
$duration = New-Object Windows.Forms.TrackBar
$duration.Location = New-Object Drawing.Point(18, 72)
$duration.Size = New-Object Drawing.Size(245, 42)
$duration.Minimum = 1
$duration.Maximum = 60
$duration.Value = 5
$duration.TickFrequency = 5
$duration.SmallChange = 1
$duration.LargeChange = 5
$duration.BackColor = $theme.White
$duration.ForeColor = $theme.Black
$duration.Add_ValueChanged({ Refresh-Ui })
$timingSection.Controls.Add($duration)

Add-Text $timingSection "Interval" 292 45 70 24 9 | Out-Null
$interval = New-Object Windows.Forms.NumericUpDown
$interval.Location = New-Object Drawing.Point(292, 75)
$interval.Size = New-Object Drawing.Size(92, 25)
$interval.Minimum = 10
$interval.Maximum = 5000
$interval.Increment = 10
$interval.Value = 100
$interval.BackColor = $theme.White
$interval.ForeColor = $theme.Black
$interval.BorderStyle = "FixedSingle"
$interval.Add_ValueChanged({ [NativeInput]::SetInterval([int]$interval.Value) })
$timingSection.Controls.Add($interval)
Add-Text $timingSection "ms" 390 75 30 24 9 | Out-Null

$controlsSection = Add-Section "Controls" 40 502 440 78
$toggleButton = Add-Button $controlsSection "Start" 24 30 390 34 { Toggle-Clicking }

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 35
$timer.Add_Tick({
    if ($state.Capture) {
        $pressed = Get-PressedInput
        if ($pressed) {
            if ($state.Capture -eq "target") { $state.Target = $pressed; Set-EngineTarget }
            else { $state.Toggle = $pressed }
            $state.Capture = $null
        }
        Refresh-Ui
        return
    }

    $toggleDown = Test-Down $state.Toggle.Vk
    if ($toggleDown -and -not $state.LastToggle) { Toggle-Clicking }
    $state.LastToggle = $toggleDown
    Refresh-Ui
})

$form.Add_Shown({ Set-EngineTarget; Refresh-Ui; $timer.Start() })
$form.Add_FormClosing({ $timer.Stop(); [NativeInput]::Stop() })
[void]$form.ShowDialog()
