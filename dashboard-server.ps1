<#
  File Command Center - lokal hjælper

  Starter en lille webserver på http://localhost:8787 (kun din egen pc kan nå den).
  Den serverer dashboardet (index.html), gemmer dine data i data.json
  og kan åbne filerne i det program, Windows har knyttet til dem (fx Excel).

  Luk vinduet (eller tryk Ctrl+C) for at stoppe.
#>
param(
    [int]$Port = 8787,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$Root      = $PSScriptRoot
$DataFile  = Join-Path $Root 'data.json'
$BackupDir = Join-Path $Root 'backups'
$IndexFile = Join-Path $Root 'index.html'
$Utf8      = New-Object System.Text.UTF8Encoding($false)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Fg {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool fAltTab);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);

    // Tvinger et vindue forrest: kobler til det aktive vindues tråd, lægger vinduet øverst og giver det fokus
    public static void Force(IntPtr h) {
        if (IsIconic(h)) ShowWindow(h, 9);
        uint pid;
        IntPtr fg = GetForegroundWindow();
        uint fgThread = GetWindowThreadProcessId(fg, out pid);
        uint me = GetCurrentThreadId();
        bool attached = false;
        if (fgThread != 0 && fgThread != me) attached = AttachThreadInput(me, fgThread, true);
        SetWindowPos(h, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
        SetWindowPos(h, (IntPtr)(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        SwitchToThisWindow(h, true);
        if (attached) AttachThreadInput(me, fgThread, false);
    }

    // Finder et Stifinder-vindue ud fra titel (mappens navn)
    public static IntPtr FindExplorerByTitle(string title) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassName(h, cls, 256);
            if (cls.ToString() != "CabinetWClass") return true;
            StringBuilder t = new StringBuilder(512);
            GetWindowText(h, t, 512);
            if (String.Equals(t.ToString(), title, StringComparison.OrdinalIgnoreCase)) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

# Filtyper der aldrig åbnes via dashboardet (programmer/scripts)
$Blocked = @('.exe','.bat','.cmd','.com','.scr','.ps1','.psm1','.vbs','.vbe','.js','.jse','.wsf','.wsh',
             '.msi','.msp','.hta','.reg','.lnk','.jar','.dll','.cpl','.pif','.url','.appref-ms')

# Pulje til parallel filtjek (så et dødt netværksdrev ikke fryser alt)
$Pool = [runspacefactory]::CreateRunspacePool(1, 8)
$Pool.Open()

# ---------------------------------------------------------------- svar-hjælpere
function Send-Text($ctx, [string]$text, [int]$code = 200, [string]$type = 'application/json; charset=utf-8') {
    $bytes = $Utf8.GetBytes($text)
    $r = $ctx.Response
    $r.StatusCode = $code
    $r.ContentType = $type
    $r.Headers.Add('Cache-Control', 'no-store')
    $r.ContentLength64 = $bytes.Length
    $r.OutputStream.Write($bytes, 0, $bytes.Length)
    $r.OutputStream.Close()
}
function Send-Json($ctx, $obj, [int]$code = 200) {
    Send-Text $ctx ($obj | ConvertTo-Json -Depth 6 -Compress) $code
}
function Send-Bytes($ctx, [byte[]]$bytes, [long]$fullSize) {
    $r = $ctx.Response
    $r.StatusCode = 200
    $r.ContentType = 'application/octet-stream'
    $r.Headers.Add('Cache-Control', 'no-store')
    $r.Headers.Add('X-File-Size', [string]$fullSize)
    $r.ContentLength64 = $bytes.Length
    $r.OutputStream.Write($bytes, 0, $bytes.Length)
    $r.OutputStream.Close()
}
function Read-Body($req) {
    $sr = New-Object System.IO.StreamReader($req.InputStream, $Utf8)
    try { $sr.ReadToEnd() } finally { $sr.Dispose() }
}

# ---------------------------------------------------------------- data
function Save-State([string]$json) {
    if (Test-Path -LiteralPath $DataFile) {
        if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
        $bak = Join-Path $BackupDir ('data-' + (Get-Date -Format 'yyyyMMdd') + '.json')
        if (-not (Test-Path -LiteralPath $bak)) {
            Copy-Item -LiteralPath $DataFile -Destination $bak
            Get-ChildItem -LiteralPath $BackupDir -Filter 'data-2*.json' |
                Sort-Object Name -Descending | Select-Object -Skip 30 | Remove-Item -Force
        }
        # Ekstra sikring: hvis der gemmes FÆRRE filer end før, gemmes først en kopi af det, der var
        try {
            $oldN = @(([IO.File]::ReadAllText($DataFile, $Utf8) | ConvertFrom-Json).files).Count
            $newN = @(($json | ConvertFrom-Json).files).Count
            if ($newN -lt $oldN) {
                $shr = Join-Path $BackupDir ('gemt-foer-sletning-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
                Copy-Item -LiteralPath $DataFile -Destination $shr
                Get-ChildItem -LiteralPath $BackupDir -Filter 'gemt-foer-sletning-*.json' |
                    Sort-Object Name -Descending | Select-Object -Skip 20 | Remove-Item -Force
            }
        } catch { }
    }
    $tmp = "$DataFile.tmp"
    [IO.File]::WriteAllText($tmp, $json, $Utf8)
    Move-Item -LiteralPath $tmp -Destination $DataFile -Force
}
function Test-Registered([string]$p) {
    if (-not (Test-Path -LiteralPath $DataFile)) { return $false }
    $d = [IO.File]::ReadAllText($DataFile, $Utf8) | ConvertFrom-Json
    foreach ($f in $d.files) { if ($f.path -eq $p) { return $true } }
    return $false
}

# ---------------------------------------------------------------- filhandlinger
function Open-Path([string]$p, [bool]$reveal) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $true
    if ($reveal) {
        $psi.FileName = 'explorer.exe'
        if (Test-Path -LiteralPath $p -PathType Container) { $psi.Arguments = '"' + $p + '"' }
        else { $psi.Arguments = '/select,"' + $p + '"' }
    } else {
        $psi.FileName = $p
    }
    [void][System.Diagnostics.Process]::Start($psi)
}

# Læser en fils bytes til forhåndsvisning (delt læseadgang, så filen godt må være åben i fx Excel)
function Read-FileBytes([string]$p, [int]$max) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'Filen findes ikke. Er netværksdrevet forbundet, eller er filen flyttet?' }
    $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $size = $fs.Length
        if ($size -gt 52428800) { throw 'Filen er for stor til forhåndsvisning' }
        $want = if ($max -gt 0) { [Math]::Min($max, $size) } else { $size }
        $buf = New-Object byte[] $want
        $off = 0
        while ($off -lt $want) { $n = $fs.Read($buf, $off, $want - $off); if ($n -le 0) { break }; $off += $n }
        return ,@($buf, $size)
    } finally { $fs.Dispose() }
}

# Henter Excel-vinduet frem (en baggrundsproces må ellers ikke selv få vinduer forrest)
function Bring-ExcelToFront {
    $done = $false
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $xl = Get-Process excel -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
                Sort-Object StartTime -Descending | Select-Object -First 1
            if ($xl) {
                [Fg]::keybd_event(0x87, 0, 0, [UIntPtr]::Zero); [Fg]::keybd_event(0x87, 0, 2, [UIntPtr]::Zero)
                [Fg]::Force($xl.MainWindowHandle)
                if ($done) { Write-Host '  Excel hentet frem'; return }
                $done = $true
            }
        } catch { Write-Host ('  Kunne ikke hente Excel frem: ' + $_.Exception.Message) -ForegroundColor Yellow; return }
    }
    if (-not $done) { Write-Host '  (Fandt ikke noget Excel-vindue at hente frem)' -ForegroundColor Yellow }
}

# Henter en Stifinder-mappe frem, når den er åbnet
function Bring-FolderToFront([string]$p) {
    $target = $p.TrimEnd('\')
    $leaf = Split-Path -Leaf $target
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep -Milliseconds 400
        try {
            [Fg]::keybd_event(0x87, 0, 0, [UIntPtr]::Zero); [Fg]::keybd_event(0x87, 0, 2, [UIntPtr]::Zero)
            $hwnd = [IntPtr]::Zero
            $shell = New-Object -ComObject Shell.Application
            foreach ($w in $shell.Windows()) {
                try {
                    $wp = $w.Document.Folder.Self.Path
                    if ($wp -and ($wp.TrimEnd('\') -ieq $target)) { $hwnd = [IntPtr][int64]$w.HWND; break }
                } catch { }
            }
            if ($hwnd -eq [IntPtr]::Zero -and $leaf) { $hwnd = [Fg]::FindExplorerByTitle($leaf) }
            if ($hwnd -ne [IntPtr]::Zero) {
                [Fg]::Force($hwnd)
                Write-Host '  Mappevindue hentet frem'
                return
            }
        } catch { Write-Host ('  Kunne ikke hente mappen frem: ' + $_.Exception.Message) -ForegroundColor Yellow; return }
    }
    Write-Host '  (Fandt ikke mappevinduet at hente frem)' -ForegroundColor Yellow
}

function Check-Paths($paths) {
    $jobs = @()
    foreach ($p in $paths) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $Pool
        [void]$ps.AddScript({
            param($p)
            try {
                if (Test-Path -LiteralPath $p) {
                    $i = Get-Item -LiteralPath $p -Force
                    @{ exists = $true; isDir = [bool]$i.PSIsContainer
                       size = $(if ($i.PSIsContainer) { $null } else { $i.Length })
                       modified = $i.LastWriteTime.ToUniversalTime().ToString('o') }
                } else { @{ exists = $false } }
            } catch { @{ exists = $false } }
        }).AddArgument($p)
        $jobs += [pscustomobject]@{ path = $p; ps = $ps; ar = $ps.BeginInvoke() }
    }
    $deadline = (Get-Date).AddSeconds(6)
    $out = @{}
    foreach ($j in $jobs) {
        $left = [int](($deadline - (Get-Date)).TotalMilliseconds)
        if ($left -lt 0) { $left = 0 }
        if ($j.ar.AsyncWaitHandle.WaitOne($left)) {
            $r = $j.ps.EndInvoke($j.ar)
            $out[$j.path] = $r[0]
            $j.ps.Dispose()
        } else {
            $out[$j.path] = @{ exists = $null; timeout = $true }
        }
    }
    return $out
}

function New-OwnerForm {
    # Usynlig, aktiv formular der tvinger dialogen forrest (ellers kan den åbne bag browseren)
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.ShowInTaskbar = $false
    $f.StartPosition = 'CenterScreen'
    $f.Size = New-Object System.Drawing.Size(1, 1)
    $f.Opacity = 0
    $f.TopMost = $true
    $f.Show()
    $f.Activate()
    [System.Windows.Forms.Application]::DoEvents()
    return $f
}
function Pick-Files([bool]$multi) {
    $owner = New-OwnerForm
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $multi
    $dlg.Title = 'Vælg filer til dashboardet'
    $dlg.Filter = 'Alle filer|*.*|Excel og CSV|*.xlsx;*.xlsm;*.xlsb;*.xls;*.csv'
    $list = @()
    if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $list = @($dlg.FileNames) }
    $owner.Dispose()
    return ,$list
}
function Pick-Folder {
    $owner = New-OwnerForm
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Vælg en mappe'
    $res = $null
    if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $res = $dlg.SelectedPath }
    $owner.Dispose()
    return $res
}
function Scan-Folder([string]$folder, [bool]$recurse) {
    $items = Get-ChildItem -LiteralPath $folder -File -Recurse:$recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith('~$') -and -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System) } |
        Select-Object -First 501
    $list = @()
    foreach ($i in $items) { $list += @{ path = $i.FullName; name = $i.BaseName } }
    $truncated = $list.Count -gt 500
    if ($truncated) { $list = @($list[0..499]) }
    return @{ files = $list; truncated = $truncated }
}

# ---------------------------------------------------------------- mappebrowser (bruges af dashboardets egen filvælger)
function Get-Places {
    $places = @()
    $seen = @{}
    $up = $env:USERPROFILE
    $cands = @()
    $map = [ordered]@{ 'Skrivebord' = 'Desktop'; 'Dokumenter' = 'Documents'; 'Overførsler' = 'Downloads' }
    foreach ($k in $map.Keys) { $cands += @{ name = $k; path = (Join-Path $up $map[$k]) } }
    foreach ($v in 'OneDrive', 'OneDriveCommercial', 'OneDriveConsumer') {
        $pp = [Environment]::GetEnvironmentVariable($v)
        if ($pp) { $cands += @{ name = (Split-Path -Leaf $pp); path = $pp } }
    }
    foreach ($cd in $cands) {
        $key = $cd.path.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        if (Test-Path -LiteralPath $cd.path) { $seen[$key] = $true; $places += $cd }
    }
    return ,$places
}
function List-Dir([string]$path, [bool]$all) {
    $exts = @('.xlsx', '.xlsm', '.xlsb', '.xls', '.csv')
    $entries = @()
    if (-not $path) {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            $entries += @{ name = $d.Name; path = $d.Name; type = 'drive' }
        }
        return @{ path = ''; parent = $null; entries = $entries; places = (Get-Places) }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw 'Mappen findes ikke eller kan ikke nås' }
    $items = Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System) } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name |
        Select-Object -First 2000
    foreach ($i in $items) {
        if ($i.PSIsContainer) {
            $entries += @{ name = $i.Name; path = $i.FullName; type = 'dir' }
        } elseif (-not $i.Name.StartsWith('~$')) {
            if ($all -or ($exts -contains $i.Extension.ToLowerInvariant())) {
                $entries += @{ name = $i.Name; path = $i.FullName; type = 'file'; size = $i.Length
                               modified = $i.LastWriteTime.ToUniversalTime().ToString('o') }
            }
        }
    }
    $parent = Split-Path -Parent $path
    if (-not $parent -or $parent -match '^\\\\[^\\]+$') { $parent = '' }
    return @{ path = $path; parent = $parent; entries = $entries }
}

# ---------------------------------------------------------------- forespørgsler
function Handle-Request($ctx) {
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath
    $method = $req.HttpMethod

    # Sikkerhed: kun localhost, kun vores egen side, og POST kræver særlig header
    if ($req.Headers['Host'] -ne "localhost:$Port") { Send-Json $ctx @{ error = 'Ugyldig host' } 403; return }
    $origin = $req.Headers['Origin']
    if ($origin -and $origin -ne "http://localhost:$Port") { Send-Json $ctx @{ error = 'Ugyldig origin' } 403; return }
    if ($method -eq 'POST' -and $req.Headers['X-Dashboard'] -ne '1') { Send-Json $ctx @{ error = 'Mangler header' } 403; return }

    if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
        if (-not (Test-Path -LiteralPath $IndexFile)) { Send-Text $ctx 'index.html mangler i mappen' 404 'text/plain; charset=utf-8'; return }
        Send-Text $ctx ([IO.File]::ReadAllText($IndexFile, $Utf8)) 200 'text/html; charset=utf-8'
        return
    }

    switch ("$method $path") {
        'GET /api/ping' { Send-Json $ctx @{ ok = $true } }

        'GET /api/state' {
            if (Test-Path -LiteralPath $DataFile) { Send-Text $ctx ([IO.File]::ReadAllText($DataFile, $Utf8)) }
            else { Send-Text $ctx 'null' }
        }

        'POST /api/state' {
            $body = Read-Body $req
            try { $null = $body | ConvertFrom-Json } catch { Send-Json $ctx @{ error = 'Ugyldig JSON' } 400; return }
            Save-State $body
            Send-Json $ctx @{ ok = $true }
        }

        'POST /api/open' {
            $b = Read-Body $req | ConvertFrom-Json
            $p = [string]$b.path
            if (-not (Test-Registered $p)) { Send-Json $ctx @{ error = 'Stien er ikke registreret i dashboardet' } 403; return }
            $ext = [IO.Path]::GetExtension($p).ToLowerInvariant()
            $isDir = Test-Path -LiteralPath $p -PathType Container
            if (-not $isDir -and ($Blocked -contains $ext)) { Send-Json $ctx @{ error = "Filtypen $ext åbnes ikke fra dashboardet" } 403; return }
            if (-not (Test-Path -LiteralPath $p)) { Send-Json $ctx @{ error = 'Filen findes ikke. Er netværksdrevet forbundet, eller er filen flyttet?' } 404; return }
            Write-Host ('  Åbner: ' + $p)
            Open-Path $p ($b.reveal -eq $true)
            Send-Json $ctx @{ ok = $true }
            if (-not ($b.reveal -eq $true) -and $isDir) { Bring-FolderToFront $p }
            elseif (-not ($b.reveal -eq $true) -and (@('.xlsx','.xlsm','.xlsb','.xls','.xltx','.xltm','.csv') -contains $ext)) { Bring-ExcelToFront }
        }

        'POST /api/file' {
            $b = Read-Body $req | ConvertFrom-Json
            $p = [string]$b.path
            if (-not (Test-Registered $p)) { Send-Json $ctx @{ error = 'Stien er ikke registreret i dashboardet' } 403; return }
            try {
                $res = Read-FileBytes $p ([int]$b.max)
                Send-Bytes $ctx $res[0] $res[1]
            } catch { Send-Json $ctx @{ error = $_.Exception.Message } 404 }
        }

        'POST /api/check' {
            $b = Read-Body $req | ConvertFrom-Json
            $results = Check-Paths @($b.paths)
            Send-Json $ctx @{ results = $results }
        }

        'POST /api/ls' {
            $b = Read-Body $req | ConvertFrom-Json
            Send-Json $ctx (List-Dir ([string]$b.path) ($b.all -eq $true))
        }

        'POST /api/pick' {
            $b = Read-Body $req | ConvertFrom-Json
            Write-Host '  Åbner Windows fildialog...'
            $paths = Pick-Files ($b.multi -eq $true)
            Send-Json $ctx @{ paths = $paths }
        }

        'POST /api/pickfolder' {
            Write-Host '  Åbner Windows mappedialog...'
            $p = Pick-Folder
            Send-Json $ctx @{ path = $p }
        }

        'POST /api/scan' {
            $b = Read-Body $req | ConvertFrom-Json
            $folder = [string]$b.folder
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { Send-Json $ctx @{ error = 'Mappen findes ikke eller kan ikke nås' } 404; return }
            Send-Json $ctx (Scan-Folder $folder ($b.recurse -eq $true))
        }

        default { Send-Json $ctx @{ error = 'Ikke fundet' } 404 }
    }
}

# ---------------------------------------------------------------- start
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() }
catch {
    Write-Host "Kunne ikke starte på port $Port. Kører dashboardet måske allerede?" -ForegroundColor Yellow
    if (-not $NoBrowser) { Start-Process "http://localhost:$Port/" }
    Start-Sleep -Seconds 3
    exit 1
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host '  Advarsel: PowerShell kører ikke i STA-tilstand - fildialoger virker muligvis ikke.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  File Command Center kører' -ForegroundColor Green
Write-Host "  Adresse:  http://localhost:$Port/"
Write-Host "  Data:     $DataFile"
Write-Host '  Luk dette vindue for at stoppe.'
Write-Host ''
if (-not $NoBrowser) { Start-Process "http://localhost:$Port/" }

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(300)) { }
        $ctx = $task.GetAwaiter().GetResult()
        try { Handle-Request $ctx }
        catch {
            Write-Host ('Fejl: ' + $_.Exception.Message) -ForegroundColor Red
            try { Send-Json $ctx @{ error = $_.Exception.Message } 500 } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    $Pool.Close()
}
