#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All
#SingleInstance Force
; ============================================================
; Script Name : eXBonez GUI Profile Manager
; Version     : 1.2
; Author      : eXBonez
; Description : A program for importing hardware profiles
;               when there is no other way besides mouse.
; Date        : 2026-01-04
; ============================================================

; --- Static Date Auto‑Updater ---
scriptFile := A_ScriptFullPath
fileContent := FileRead(scriptFile)

today := FormatTime(A_Now, "yyyy-MM-dd")

if RegExMatch(fileContent, "Date\s*:\s*(.*)", &m) {
    newContent := RegExReplace(fileContent, "Date\s*:\s*(.*)", "Date        : 2026-01-04
    if (newContent != fileContent) {
        FileDelete(scriptFile)
        FileAppend(newContent, scriptFile)
    }
}
; --- End Auto‑Updater ---

SetWorkingDir A_ScriptDir

gamesFile := A_ScriptDir . "\games.ini"
; ===== Default initialization if games.ini does NOT exist =====
if !FileExist(gamesFile) {
    ; Create minimal INI structure
    IniWrite("Default", gamesFile, "Config", "SelectedDevice")
    IniWrite("*", gamesFile, "Config", "SelectedExtension")
    IniWrite("1000", gamesFile, "Config", "DefaultProfileDelay")  ; ← ADD THIS LINE!
    IniWrite("Default", gamesFile, "Devices", "1")
    IniWrite("*", gamesFile, "DeviceExtensions", "Default")
    

    ; Also set runtime defaults
    selectedDevice := "Default"
    deviceExtensions := Map()
    deviceExtensions["Default"] := ["*"]
    deviceCurrentExt := Map()
    deviceCurrentExt["Default"] := "*"
    currentProfileExtension := "*"
    EnsureDefaultIniKeys()
}

profileDir := IniRead(gamesFile, "Config", "ProfilesDir", A_ScriptDir . "\Profiles")
backupDir := A_ScriptDir . "\Backups"
deviceGuiExe := IniRead(gamesFile, "Config", "DeviceGuiExe", "")

; FIX: Properly handle default profile delay (for closing GUI after import)
currentDelay := IniRead(gamesFile, "Config", "DefaultProfileDelay", "")
if (currentDelay = "" || !RegExMatch(currentDelay, "^\d+$")) {
    ; Write the new default if missing or invalid
    defaultProfileDelay := 1000  ; Your default value
    IniWrite(defaultProfileDelay, gamesFile, "Config", "DefaultProfileDelay")
} else {
    defaultProfileDelay := Integer(currentDelay)
}

bgColorCfg := IniRead(gamesFile, "Theme", "BgColor", "0xB0BEE3")
textColorCfg := IniRead(gamesFile, "Theme", "TextColor", "0x000000")
sortGamesMode := IniRead(gamesFile, "Sort", "Games", "Alphabetical")
sortProfilesMode := "Alphabetical"
sortOrder := IniRead(gamesFile, "Sort", "Order", "Ascending")
defaultProfile := IniRead(gamesFile, "Config", "DefaultProfile", "")
lastTab := IniRead(gamesFile, "Config", "LastTab", 1)
lastExeDir := IniRead(gamesFile, "Config", "LastExeDir", "")
trayMinimize := IniRead(gamesFile, "Config", "TrayMinimize", 1)

; Device / extension system
selectedDevice := IniRead(gamesFile, "Config", "SelectedDevice", "")
devices := []
deviceExtensions := Map()     ; deviceName -> Array of extensions
deviceCurrentExt := Map()     ; deviceName -> current extension string
currentProfileExtension := "*"  ; active extension for selected device

if (lastTab < 1 || lastTab > 4)
    lastTab := 1

games := Map()
profiles := Map()
fullGameNames := []
fullProfileNames := []
current_notes_game := ""
current_notes_profile := ""

EnsureDefaultIniKeys() {
    global gamesFile
    ; List of required config keys with defaults
    requiredKeys := Map(
        "SelectedDevice", "Default",
        "SelectedExtension", "*",
        "DefaultProfileDelay", "1000",
        "DeviceGuiExe", "",
        "ProfilesDir", A_ScriptDir . "\Profiles",
        "LastTab", "1"
    )
    
    for key, defaultValue in requiredKeys {
        currentValue := IniRead(gamesFile, "Config", key, "")
        if (currentValue = "") {
            IniWrite(defaultValue, gamesFile, "Config", key)
        }
    }
}


CurrentIsoTimestamp() {
    return FormatTime(A_Now, "yyyy-MM-dd'T'HH:mm:ss")
}

ArrayReverse(arr) {
    out := []
    Loop arr.Length
        out.Push(arr[arr.Length + 1 - A_Index])
    return out
}

HexToRGB(hex) {
    if (SubStr(hex, 1, 2) = "0x")
        hex := SubStr(hex, 3)
    r := "0x" . SubStr(hex, 1, 2)
    g := "0x" . SubStr(hex, 3, 2)
    b := "0x" . SubStr(hex, 5, 2)
    return [r, g, b]
}

RelativeLuminance(r, g, b) {
    r := r/255, g := g/255, b := b/255
    r := (r <= 0.03928) ? (r/12.92) : (((r+0.055)/1.055)**2.4)
    g := (g <= 0.03928) ? (g/12.92) : (((g+0.055)/1.055)**2.4)
    b := (b <= 0.03928) ? (b/12.92) : (((b+0.055)/1.055)**2.4)
    return 0.2126*r + 0.7152*g + 0.0722*b
}

ContrastRatio(fgHex, bgHex) {
    fg := HexToRGB(fgHex), bg := HexToRGB(bgHex)
    L1 := RelativeLuminance(fg[1], fg[2], fg[3])
    L2 := RelativeLuminance(bg[1], bg[2], bg[3])
    if (L1 < L2) {
        t := L1, L1 := L2, L2 := t
    }
    return (L1+0.05)/(L2+0.05)
}

PickBestTextColor(bgHex) {
    return (ContrastRatio("000000", SubStr(bgHex, 3)) >= ContrastRatio("FFFFFF", SubStr(bgHex, 3))) ? "0x000000" : "0xFFFFFF"
}

ApplyTextColor(textColor) {
    global mainGui
    opt := "c" . SubStr(textColor, 3)
    for ctrlItem in mainGui
        try ctrlItem.SetFont(opt)
}

PickColorFromDialog(start := "0xFFFFFF") {
    if (start = "" || !RegExMatch(start, "^0x[0-9A-Fa-f]{6}$"))
        start := "0xFFFFFF"

    start := Integer(start)
    r := (start >> 16) & 0xFF
    g := (start >> 8) & 0xFF
    b := start & 0xFF
    initialR := r, initialG := g, initialB := b
    initialHex := "0x" . Format("{:02X}{:02X}{:02X}", r, g, b)
    colorGui := Gui("+ToolWindow +AlwaysOnTop", "Pick Color")
    colorGui.SetFont("s11")
    colorGui.AddText("x10 y10 w200", "Red")
    sR := colorGui.AddSlider("x10 y30 w200 Range0-255 AltSubmit", r)
    colorGui.AddText("x10 y60 w200", "Green")
    sG := colorGui.AddSlider("x10 y80 w200 Range0-255 AltSubmit", g)
    colorGui.AddText("x10 y110 w200", "Blue")
    sB := colorGui.AddSlider("x10 y130 w200 Range0-255 AltSubmit", b)
    preview := colorGui.AddProgress("x10 y170 w200 h40 Background" . Format("{:02X}{:02X}{:02X}", r, g, b), 0)
    colorGui.AddText("x10 y220 w200", "Hex Code:")
    hexEdit := colorGui.AddEdit("x10 y240 w200", initialHex)
    ok := colorGui.AddButton("x10 y280 w95 h30", "OK")
    revert := colorGui.AddButton("x110 y280 w95 h30", "Revert to Last")
    updateFromSliders := (*) => (hex := "0x" . Format("{:02X}{:02X}{:02X}", sR.Value, sG.Value, sB.Value), preview.Opt("Background" . SubStr(hex, 3)), hexEdit.Value := hex)
    updateFromHex := (*) => (hex := Trim(hexEdit.Value), hex := RegExReplace(hex, "^0x|#", ""), (StrLen(hex) = 6 ? (r := "0x" . SubStr(hex, 1, 2), g := "0x" . SubStr(hex, 3, 2), b := "0x" . SubStr(hex, 5, 2), sR.Value := r, sG.Value := g, sB.Value := b, preview.Opt("Background" . hex)) : 0))
    revertToInitial := (*) => (sR.Value := initialR, sG.Value := initialG, sB.Value := initialB, hexEdit.Value := initialHex, preview.Opt("Background" . SubStr(initialHex, 3)))
    sR.OnEvent("Change", updateFromSliders)
    sG.OnEvent("Change", updateFromSliders)
    sB.OnEvent("Change", updateFromSliders)
    hexEdit.OnEvent("Change", updateFromHex)
    revert.OnEvent("Click", revertToInitial)
    picked := ""
    ok.OnEvent("Click", (*) => (picked := hexEdit.Value, colorGui.Destroy()))
    colorGui.Show("AutoSize Center")
    WinWaitClose(colorGui.Hwnd)
    if (SubStr(picked, 1, 1) = "#")
        picked := "0x" . SubStr(picked, 2)
    if (!RegExMatch(picked, "^0x[0-9A-Fa-f]{6}$"))
        picked := "0xFFEAD9"
    return picked
}

LoadGames() {
    global gamesFile, games
    games := Map()
    if !FileExist(gamesFile)
        return
    try raw := IniRead(gamesFile, "Games")
    catch
        return
    if (raw = "")
        return
    for line in StrSplit(raw, "`n", "`r") {
        line := Trim(line)
        if (line = "" || !InStr(line, "="))
            continue
        p := StrSplit(line, "=")
        key := Trim(p[1]), val := Trim(p[2])
        if !InStr(key, ".")
            continue
        kp := StrSplit(key, ".")
        gameKey := RegExReplace(kp[1], "\s"), field := kp[2]
        if !games.Has(gameKey)
            games[gameKey] := Map("Exe","", "Profiles","", "PostImportDelay",1500, "LaunchExe",1, "CloseManager",1, "Added","", "LastPlayed","", "LaunchCount",0)
        games[gameKey][field] := val
    }
}

RepairGamesIni() {
    global gamesFile

    try raw := IniRead(gamesFile, "Games")
    catch
        return

    if (raw = "")
        return

    fixed := false

    for line in StrSplit(raw, "`n", "`r") {
        line := Trim(line)
        if (line = "" || !InStr(line, "="))
            continue

        p := StrSplit(line, "=")
        key := Trim(p[1])
        val := Trim(p[2])

        ; Detect incorrect ".Profile=" keys
        if InStr(key, ".Profile") && !InStr(key, ".Profiles") {
            game := StrReplace(key, ".Profile")
            correctKey := game . ".Profiles"

            ; Write corrected key
            IniWrite(val, gamesFile, "Games", correctKey)

            ; Remove incorrect key
            IniDelete(gamesFile, "Games", key)

            fixed := true
        }
    }

    if (fixed) {
        ; Reload games after repair
        LoadGames()
    }
}

LoadProfiles() {
    global gamesFile, profiles
    profiles := Map()
    if !FileExist(gamesFile)
        return
    try raw := IniRead(gamesFile, "Profiles")
    catch
        return
    if (raw = "")
        return
    for line in StrSplit(raw, "`n", "`r") {
        line := Trim(line)
        if (line = "" || !InStr(line, "="))
            continue
        p := StrSplit(line, "=")
        key := Trim(p[1]), val := Trim(p[2])
        if !InStr(key, ".")
            continue
        kp := StrSplit(key, ".")
        profileKey := kp[1], field := kp[2]
        if !profiles.Has(profileKey)
            profiles[profileKey] := Map("Notes","")
        profiles[profileKey][field] := val
    }
}

SaveGameToIni(gameName, exe, profs, delay, launch, added := "", last := "", count := "", closeManager := 1) {
    global gamesFile
    key := RegExReplace(gameName, "\s")
    IniWrite(exe, gamesFile, "Games", key . ".Exe")
    IniWrite(profs, gamesFile, "Games", gameName . ".Profiles")
    IniWrite(delay, gamesFile, "Games", gameName . ".PostImportDelay")
    IniWrite(launch, gamesFile, "Games", gameName . ".LaunchExe")
    IniWrite(closeManager, gamesFile, "Games", gameName . ".CloseManager")
    if (added != "")
        IniWrite(added, gamesFile, "Games", gameName . ".Added")
    if (last != "")
        IniWrite(last, gamesFile, "Games", gameName . ".LastPlayed")
    if (count != "")
        IniWrite(count, gamesFile, "Games", gameName . ".LaunchCount")
}

RemoveGameFromIni(gameName) {
    global gamesFile
    for f in ["Exe","Profiles","PostImportDelay","LaunchExe","Added","LastPlayed","LaunchCount"]
        IniDelete(gamesFile, "Games", gameName . "." . f)
}

SortGameNames(games, mode, order) {
    names := []
    For n, dummy in games
        names.Push(n)
    
    if (names.Length < 2)
        return names
    
    if (mode = "Alphabetical") {
        s := ""
        for v in names
            s .= v . "`n"
        s := RTrim(s, "`n")
        s := Sort(s)
        names := StrSplit(s, "`n")
    } else {
        ; Create string to sort
        s := ""
        for n in names {
            t := ""
            if (mode = "TimeAdded") {
                t := games[n]["Added"]
            } else if (mode = "LastPlayed") {
                t := games[n]["LastPlayed"]
            }
            
            if (t = "") {
                if (mode = "TimeAdded")
                    t := "9999-12-31T23:59:59"
                else if (mode = "LastPlayed")
                    t := "1900-01-01T00:00:00"
            }
            
            ; Add timestamp and name as one line
            s .= t . "|" . n . "`n"
        }
        
        ; Remove trailing newline and sort
        s := RTrim(s, "`n")
        s := Sort(s)  ; ISO timestamps sort correctly as strings
        
        ; Parse sorted result
        names := []
        for line in StrSplit(s, "`n") {
            p := StrSplit(line, "|")
            if (p.Length >= 2)
                names.Push(p[2])
        }
    }
    
    if (order = "Descending")
        names := ArrayReverse(names)
    
    return names
}

SortProfileNames(dir, mode, order) {
    global currentProfileExtension
    items := []
    if !DirExist(dir)
        return items
    pattern := (currentProfileExtension = "*" || currentProfileExtension = "") ? "*.*" : "*." . currentProfileExtension
    loop Files, dir . "\" . pattern
        items.Push(A_LoopFileName)
    if (mode = "Alphabetical" && items.Length > 1) {
        s := ""
        for v in items
            s .= v . "`n"
        s := RTrim(s, "`n")
        s := Sort(s)  ; AHK v2: Sort returns the sorted string
        items := StrSplit(s, "`n")
    }
    if (order = "Descending")
        items := ArrayReverse(items)
    return items
}

CaptureImportButtonCoords() {
    global gamesFile, deviceGuiExe, clickCaptureCount, clickCapturedList, overlay

    ; Ask how many clicks to capture
    countGui := Gui("+ToolWindow +AlwaysOnTop", "Click Count")
    countGui.SetFont("s11")
    countGui.AddText("x10 y10 w200", "How many clicks to record?")
    dd := countGui.AddDropDownList("x10 y40 w120", ["1","2","3","4","5","6","7","8","9","10"])  ; Changed to 10 options
    dd.Value := 1
    ok := countGui.AddButton("x10 y80 w120 h28", "OK")

    ok.OnEvent("Click", (*) => (
        clickCaptureCount := Integer(dd.Text),
        clickCapturedList := [],
        countGui.Destroy(),
        StartClickCaptureOverlay()
    ))

    countGui.Show("AutoSize Center")
}

StartClickCaptureOverlay() {
    global deviceGuiExe, clickCaptureCount, overlay, clickCounterText

    if (deviceGuiExe = "" || !FileExist(deviceGuiExe)) {
        MsgBox("Device GUI EXE is not set or missing.")
        return
    }

    ; Extract EXE name
    processName := SubStr(deviceGuiExe, InStr(deviceGuiExe, "\",, -1) + 1)

    ; Launch GUI EXE
    Run(deviceGuiExe)
    Sleep(1500)

    ; Flexible window activation
    if WinExist("ahk_exe " . processName)
        WinActivate("ahk_exe " . processName)
    else if WinExist("Device")
        WinActivate("Device")
    else if WinExist("GUI")
        WinActivate("GUI")
    else {
        MsgBox("Could not find Device GUI window.")
        return
    }

    Sleep(300)
    CoordMode("Mouse", "Screen")

    ; Show overlay with click counter
    overlay := Gui("-Caption +AlwaysOnTop +ToolWindow -Theme")
    overlay.SetFont("s11")
    overlay.BackColor := "0xEEAA99"
    overlay.Opt("+LastFound")
    WinSetTransparent(200)

    ; Add counter text
    overlay.AddText("x10 y10 w320 h20 Center", "Click Counter:")
    clickCounterText := overlay.AddText("x10 y30 w320 h30 Center", clickCaptureCount . " clicks left")
    clickCounterText.SetFont("Bold")  ; AHK v2: Set bold font separately

    overlay.AddText("x10 y65 w320 h20", "Press F8 to capture each click")
    overlay.Show("Center w340 h90")

    ; Enable F8 capture with a slight delay to prevent double registration
    Sleep(100) ; Small delay to ensure hotkey is ready
    Hotkey("F8", MultiClickCapture_Fire, "On")
}

MultiClickCapture_Fire(*) {
    global clickCaptureCount, clickCapturedList, gamesFile, deviceGuiExe, overlay, clickCounterText

    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)
    clickCapturedList.Push([x, y])

    ; Update counter
    clicksLeft := clickCaptureCount - clickCapturedList.Length
    if (clicksLeft > 0) {
        clickCounterText.Text := clicksLeft . " click" . (clicksLeft = 1 ? "" : "s") . " left"
        return
    }

    ; If all clicks captured
    if (clickCapturedList.Length >= clickCaptureCount) {
        ; Disable hotkey immediately
        Hotkey("F8", "Off")

        ; Save number of clicks captured in this session
        IniWrite(clickCaptureCount, gamesFile, "Config", "ImportClickCount")

        ; Save each click coordinate
        Loop clickCapturedList.Length {
            IniWrite(clickCapturedList[A_Index][1], gamesFile, "Config", "ImportButtonX" A_Index)
            IniWrite(clickCapturedList[A_Index][2], gamesFile, "Config", "ImportButtonY" A_Index)
        }

        ; Also save first click as default single-click coordinates for compatibility
        if (clickCapturedList.Length >= 1) {
            IniWrite(clickCapturedList[1][1], gamesFile, "Config", "ImportButtonX")
            IniWrite(clickCapturedList[1][2], gamesFile, "Config", "ImportButtonY")
        }

        ; Close the red overlay
        if (overlay) {
            overlay.Destroy()
        }

        ; Show green success message overlay
        successOverlay := Gui("-Caption +AlwaysOnTop +ToolWindow -Theme")
        successOverlay.SetFont("s11 Bold")
        successOverlay.BackColor := "0x90EE90"  ; Light green
        successOverlay.Opt("+LastFound")
        WinSetTransparent(220)

        successOverlay.AddText("x10 y10 w320 h40 Center cGreen", "? Recording Success!")
        successOverlay.AddText("x10 y50 w320 h30 Center", "Saved " . clickCaptureCount . " click(s)")
        successOverlay.Show("Center w340 h90")

        ; Wait 3 seconds
        Sleep(3000)

        ; Close success overlay
        successOverlay.Destroy()

        ; Extract process name and close Device GUI
        if (deviceGuiExe != "") {
            processName := SubStr(deviceGuiExe, InStr(deviceGuiExe, "\",, -1) + 1)
            if ProcessExist(processName) {
                ProcessClose(processName)
            }
        }
    }
}

TestImportClick(*) {
    global gamesFile, deviceGuiExe

    if (deviceGuiExe = "" || !FileExist(deviceGuiExe)) {
        MsgBox("Device GUI EXE is not set or missing.")
        return
    }

    ; Extract process name
    processName := SubStr(deviceGuiExe, InStr(deviceGuiExe, "\",, -1) + 1)

    ; Read how many clicks were captured last time
    clickCount := IniRead(gamesFile, "Config", "ImportClickCount", 0)
    if (clickCount = 0) {
        MsgBox("No captured clicks found. Run 'Capture Import Button' first.")
        return
    }

    ; Load exactly that many clicks
    clickList := []
    Loop clickCount {
        x := IniRead(gamesFile, "Config", "ImportButtonX" A_Index, "")
        y := IniRead(gamesFile, "Config", "ImportButtonY" A_Index, "")
        if (x = "" || y = "")
            break
        clickList.Push([x, y])
    }

    if (clickList.Length = 0) {
        MsgBox("No valid click coordinates found.")
        return
    }

    ; Launch GUI EXE
    Run(deviceGuiExe)
    Sleep(1000)

    ; Activate window
    if WinExist("ahk_exe " . processName)
        WinActivate("ahk_exe " . processName)
    else if WinExist("Device")
        WinActivate("Device")
    else if WinExist("GUI")
        WinActivate("GUI")
    else {
        MsgBox("Could not find Device GUI window.")
        return
    }

    Sleep(300)
    CoordMode("Mouse", "Screen")

    ; Replay each captured click
    for coords in clickList {
        MouseMove(coords[1], coords[2], 10)
        Sleep(200)
        Click
        Sleep(300)
    }

    ; Wait 1 second before closing
    Sleep(1000)

    ; Close GUI EXE
    if ProcessExist(processName)
        ProcessClose(processName)
}

ImportProfile(path, customDelay := "") {
    global deviceGuiExe, gamesFile, profileDir, defaultProfileDelay
    
    ; Debug: Uncomment to see the delay value
    ; MsgBox("Profile delay: " . defaultProfileDelay . "ms", "Debug", "T2")
    
    if (deviceGuiExe = "") {
        MsgBox("Device GUI EXE is not set.`nPlease select it in Settings.", "Error", "Iconx")
        return
    }
    if !FileExist(deviceGuiExe) {
        MsgBox("Device GUI software not found at:`n" . deviceGuiExe, "Error", "Iconx")
        return
    }
    if !FileExist(path) {
        MsgBox("Profile file not found.")
        return
    }
    
    ; Check for multi-click coordinates first
    clickCount := IniRead(gamesFile, "Config", "ImportClickCount", 0)
    if (clickCount > 0) {
        ; Use multi-click system
        clickList := []
        Loop clickCount {
            x := IniRead(gamesFile, "Config", "ImportButtonX" A_Index, "")
            y := IniRead(gamesFile, "Config", "ImportButtonY" A_Index, "")
            if (x = "" || y = "")
                break
            clickList.Push([x, y])
        }
        
        if (clickList.Length = 0) {
            MsgBox("No valid multi-click coordinates found.", "Error", "Iconx")
            return
        }
    } else {
        ; Fall back to single-click coordinates
        btnX := IniRead(gamesFile, "Config", "ImportButtonX", "")
        btnY := IniRead(gamesFile, "Config", "ImportButtonY", "")
        if (btnX = "" || btnY = "") {
            MsgBox("Import button coordinates not set.", "Error", "Iconx")
            return
        }
        clickList := [[btnX, btnY]]
    }
    
    ; Extract process name
    processName := ""
    if (deviceGuiExe != "")
        processName := SubStr(deviceGuiExe, InStr(deviceGuiExe, "\",, -1) + 1)
    
    ; Launch GUI if not running
    if !ProcessExist(processName) {
        Run(deviceGuiExe)
        Sleep(1500)
    }
    
    ; Flexible window detection
    if !(WinWait("ahk_exe " . processName, "", 5)
        || WinWait("Device", "", 5)
        || WinWait("GUI", "", 5)) 
    {
        MsgBox("Could not find Device GUI window.")
        return
    }
    
    ; Activate window
    if WinExist("ahk_exe " . processName)
        WinActivate("ahk_exe " . processName)
    else if WinExist("Device")
        WinActivate("Device")
    else if WinExist("GUI")
        WinActivate("GUI")
    
    Sleep(300)
    CoordMode("Mouse", "Screen")
    
    ; Perform all clicks
    for coords in clickList {
        MouseMove(coords[1], coords[2], 10)
        Sleep(100)
        Click
        Sleep(300)
    }
    
    ; Wait for file dialog
    WinWait("ahk_class #32770", "", 10)
    if !WinExist("ahk_class #32770") {
        MsgBox("File open dialog did not appear.")
        return
    }
    
    WinActivate("ahk_class #32770")
    Sleep(600)
    ControlSetText(path, "Edit1", "ahk_class #32770")
    Sleep(100)
    ControlClick("Button1", "ahk_class #32770", , "Left", 1, "NA")
    Sleep(100)
    Send("{Enter}")
    
    ; WAIT for profile to load into hardware before closing
    ; Use custom delay if provided, otherwise use default
    delayToUse := (customDelay != "") ? customDelay : defaultProfileDelay
    Sleep(delayToUse)
    
    ; Close Device GUI
    if ProcessExist(processName)
        ProcessClose(processName)
}

; Safe launch function for Device GUI Editor
LaunchDeviceGuiEditor(*) {
    global deviceGuiExe
    if (deviceGuiExe = "") {
        MsgBox(
            "Device GUI EXE is not set yet.`n`n"
          . "Please go to Settings tab → 'Select Device GUI EXE'`n"
          . "to choose the executable path.",
            "Device GUI Editor - Not Configured",
            "Icon! T5"
        )
        return
    }
    if !FileExist(deviceGuiExe) {
        MsgBox(
            "The selected Device GUI EXE path does not exist:`n" deviceGuiExe "`n`n"
          . "Please go to Settings → 'Select Device GUI EXE'`n"
          . "and choose a valid executable.",
            "Device GUI Editor - File Missing",
            "Iconx T6"
        )
        return
    }
    try Run(deviceGuiExe)
    catch as err {
        MsgBox("Failed to launch Device GUI:`n" err.Message, "Launch Error", "Iconx")
    }
}

; ===== CLI Launch Mode (Desktop Shortcut Support) =====
; ===== CLI Launch Mode (Desktop Shortcut Support) =====
if (A_Args.Length > 0 && A_Args[1] = "/launch") {
    if (A_Args.Length < 2)
        ExitApp

    cliGameName := A_Args[2]

    ; Load game list
    LoadGames()

    ; Loose matching
    if !games.Has(cliGameName) {
        for name, ignore in games {
            if (StrLower(RegExReplace(name, "\W")) = StrLower(RegExReplace(cliGameName, "\W"))) {
                cliGameName := name
                break
            }
        }
    }

    ; If still not found, exit silently
    if !games.Has(cliGameName)
        ExitApp

    ; Update LastPlayed + LaunchCount BEFORE launching
    now := CurrentIsoTimestamp()
    launchCount := games[cliGameName]["LaunchCount"]
    if (launchCount = "")
        launchCount := 0
    launchCount++

    SaveGameToIni(
        cliGameName,
        games[cliGameName]["Exe"],
        games[cliGameName]["Profiles"],
        games[cliGameName]["PostImportDelay"],
        games[cliGameName]["LaunchExe"],
        games[cliGameName]["Added"],
        now,
        launchCount,
        games[cliGameName].Has("CloseManager") ? games[cliGameName]["CloseManager"] : 1
    )

    ; Launch the game normally
    LaunchGameByName(cliGameName)

    ExitApp  ; ← CLI SHOULD ALWAYS EXIT AFTER LAUNCHING
}

LaunchGameByName(cliGameName) {
    global games, gamesFile, defaultProfileDelay
    local lastPlayed, count
    exe := games[cliGameName]["Exe"]
    prof := games[cliGameName]["Profiles"]
    delay := games[cliGameName]["PostImportDelay"]
    launch := games[cliGameName]["LaunchExe"]
    closeManager := games[cliGameName].Has("CloseManager") ? games[cliGameName]["CloseManager"] : 1
    
    ; Get the game's GUI close delay
    guiCloseDelay := IniRead(gamesFile, "Games", cliGameName . ".GuiCloseDelay", defaultProfileDelay)
    
    ; Always update LastPlayed timestamp
    lastPlayed := CurrentIsoTimestamp()
    
    ; Get current count
    count := games[cliGameName]["LaunchCount"]
    if (count = "")
        count := 0
    count++
    
    if (prof != "")
        ImportProfile(prof, guiCloseDelay)  ; ← PASS THE GAME'S DELAY
    
    if (launch = 1 && exe != "") {
        if (delay != "" && delay is integer)
            Sleep(delay)
        
        SaveGameToIni(cliGameName, exe, prof, delay, launch, 
                      games[cliGameName]["Added"], lastPlayed, count, closeManager)
        
        processName := "DeviceGui.exe"
        if WinExist("ahk_exe " . processName)
            WinClose("ahk_exe " . processName)
        
        Run('cmd.exe /c timeout /t 1 /nobreak >nul & start "" "' . exe . '"', , "Hide")
        
        ; Close the Manager ONLY if checkbox is checked
        if (closeManager = 1) {
            Sleep(500)  ; Small delay to ensure game starts
            ExitApp
        }
        ; If closeManager = 0, DON'T ExitApp - stay open
    } else {
        SaveGameToIni(cliGameName, exe, prof, delay, launch, 
                      games[cliGameName]["Added"], lastPlayed, count, closeManager)
        
        ; Close the Manager ONLY if checkbox is checked
        if (closeManager = 1) {
            Sleep(500)
            ExitApp
        }
        ; If closeManager = 0, DON'T ExitApp - stay open
    }
}

mainGui := Gui("+Resize +MinSize525x750 -Theme +OwnDialogs", "Device GUI Manager")
mainGui.OnEvent("Close", ExitWithDeviceGuiClose)
mainGui.SetFont("s11")
mainGui.BackColor := bgColorCfg
tabs := mainGui.AddTab3("x10 y10 w515 h720", ["Game Launcher", "Profile Manager", "Game Editor", "Settings"])
tabs.Value := lastTab
ApplyTextColor(textColorCfg)

; TAB 1 - Game Launcher
tabs.UseTab(1)
mainGui.AddText("x20 y50 w60", "Search:")
launcherSearchEdit := mainGui.AddEdit("x80 y50 w420", "")
mainGui.AddText("x20 y80 w480 Center", "Select Game:")
lbLauncher := mainGui.AddListBox("x20 y105 w480 h370 AltSubmit +Border")
lbLauncher.SetFont("s11")
launcherSelLabel := mainGui.AddText("x20 y480 w480", "")
launcherNotesLabel := mainGui.AddText("x20 y510 w200", "Notes for selected game:")
launcherNotesEdit := mainGui.AddEdit("x20 y530 w480 h60 +Multi +Border")
launchBtn := mainGui.AddButton("x20 y600 w225 h30", "Launch Game")
launcherOpenFolderBtn := mainGui.AddButton("x250 y600 w225 h30", "Open Profiles Folder")
launcherLaunchEditorBtn := mainGui.AddButton("x20 y640 w225 h30", "Launch Device GUI Editor")
launcherExitBtn := mainGui.AddButton("x250 y640 w225 h30", "Exit Program")

; TAB 2 - Profile Manager
tabs.UseTab(2)
mainGui.AddText("x20 y50 w60", "Search:")
profilesSearchEdit := mainGui.AddEdit("x80 y50 w420", "")
mainGui.AddText("x20 y80 w480 Center", "Select Profile:")
lbProfiles := mainGui.AddListBox("x20 y105 w480 h370 AltSubmit +Border")
lbProfiles.SetFont("s11")
profileSelLabel := mainGui.AddText("x20 y480 w480", "")
profilesNotesLabel := mainGui.AddText("x20 y510 w200", "Notes for selected profile:")
profilesNotesEdit := mainGui.AddEdit("x20 y530 w480 h60 +Multi +Border")
profilesImportBtn := mainGui.AddButton("x20 y600 w225 h30", "Import Profile")
profilesOpenFolderBtn := mainGui.AddButton("x250 y600 w225 h30", "Open Profiles Folder")
profilesBackupBtn := mainGui.AddButton("x20 y640 w225 h30", "Backup Profile")
profilesSetFolderBtn := mainGui.AddButton("x250 y640 w225 h30", "Set Profiles Folder")
profilesLaunchEditorBtn := mainGui.AddButton("x20 y680 w225 h30", "Launch Device GUI Editor")
profilesExitBtn := mainGui.AddButton("x250 y680 w225 h30", "Exit Program")

; TAB 3 - Game Editor
tabs.UseTab(3)
mainGui.AddText("x20 y50 w60", "Search:")
editorSearchEdit := mainGui.AddEdit("x80 y50 w420", "")
mainGui.AddText("x20 y80 w480 Center", "Select Game:")
lbGames := mainGui.AddListBox("x20 y105 w480 h190 AltSubmit +Border")
lbGames.SetFont("s11")
selGameLabel := mainGui.AddText("x20 y300 w480", "")
editorAddBtn := mainGui.AddButton("x20 y325 w225 h30", "Add / Update")
editorRemoveBtn := mainGui.AddButton("x250 y325 w225 h30", "Remove")
editorCreateShortcutBtn := mainGui.AddButton("x20 y365 w225 h30", "Create Shortcut")
editorClearBtn := mainGui.AddButton("x250 y365 w225 h30", "Clear Fields")
editorOpenFolderBtn := mainGui.AddButton("x20 y405 w225 h30", "Open Profiles Folder")
editorExitBtn := mainGui.AddButton("x250 y405 w225 h30", "Exit")
mainGui.AddText("x20 y445 w480", "Game EXE Path:")
gameExeEdit := mainGui.AddEdit("x20 y465 w365 +Border")
editorBrowseExeBtn := mainGui.AddButton("x395 y465 w105 h26", "Browse")
editorOpenExeFolderBtn := mainGui.AddButton("x395 y495 w120 h26", "Open EXE Folder")
mainGui.AddText("x20 y535 w480", "Game Name:")
gameNameEdit := mainGui.AddEdit("x20 y555 w480 +Border")
mainGui.AddText("x20 y595 w480", "Profile Path:")
gameProfileEdit := mainGui.AddEdit("x20 y615 w365 +Border")
editorBrowseProfileBtn := mainGui.AddButton("x395 y615 w105 h26", "Browse")
mainGui.AddText("x20 y655 w200", "Game Launch Delay (ms):")
gameDelayEdit := mainGui.AddEdit("x20 y675 w150 +Border")
launchExeCheckbox := mainGui.AddCheckBox("x175 y675", "Launch with EXE")
launchExeCheckbox.Value := 1
closeManagerCheckbox := mainGui.AddCheckBox("x320 y675", "Close Manager after Launch")
closeManagerCheckbox.Value := 1
mainGui.AddText("x193 y700 w140 h20", "GUI Close Delay (ms):")  ; ← MOVED RIGHT 20 PIXELS (was x175)
guiCloseDelayEdit := mainGui.AddEdit("x305 y698 w65 h22 +Border Number", defaultProfileDelay)

; TAB 4 - Settings
tabs.UseTab(4)
settingsColorsBox := mainGui.AddGroupBox("x20 y50 w460 h110", "Colors")
bgColorLabel := mainGui.AddText("x40 y80 w80 h20", "BG Color:")
bgColorBtn := mainGui.AddButton("x120 y78 w100 h24", "Pick")
textColorPreview := mainGui.AddText("x240 y78 w200 h24 Center", "Text Preview")

settingsSortBox := mainGui.AddGroupBox("x20 y170 w460 h150", "Sorting")
mainGui.AddText("x40 y200 w120 h20", "Sort Games By:")
gamesSortDrop := mainGui.AddDropDownList("x160 y198 w140 +Border", ["Alphabetical", "TimeAdded", "LastPlayed"])
mainGui.AddText("x310 y200 w80 h20", "Order:")
orderSortDrop := mainGui.AddDropDownList("x360 y198 w100 +Border", ["Ascending", "Descending"])

gamesSortDrop.Text := sortGamesMode
orderSortDrop.Text := sortOrder

settingsDeviceBox := mainGui.AddGroupBox("x20 y330 w460 h140", "Device GUI Automation")
launchEditorBtn := mainGui.AddButton("x40 y360 w180 h26", "Launch Device GUI Editor")
captureImportBtn := mainGui.AddButton("x240 y360 w180 h26", "Capture Import Button")
openProfilesBtn := mainGui.AddButton("x40 y390 w180 h26", "Open Program Folder")
testImportBtn := mainGui.AddButton("x240 y390 w180 h26", "Test Import Click")
selectDeviceGuiExeBtn := mainGui.AddButton("x40 y420 w180 h26", "Select Device GUI EXE")
openProfileFolderBtn := mainGui.AddButton("x240 y420 w180 h26", "Open Profile Folder")  ; NEW BUTTON

; New Devices group at the bottom (A3)
settingsDevicesBox := mainGui.AddGroupBox("x20 y480 w460 h140", "Devices")
mainGui.AddText("x40 y510 w80 h20", "Device:")
devicesDrop := mainGui.AddDropDownList("x120 y508 w200 +Border")
addDeviceBtn := mainGui.AddButton("x330 y508 w70 h24", "Add")
deleteDeviceBtn := mainGui.AddButton("x405 y508 w70 h24", "Delete")

mainGui.AddText("x40 y540 w120 h20", "Profile Ext:")
profileExtDrop := mainGui.AddDropDownList("x120 y538 w140 +Border")
addExtEdit := mainGui.AddEdit("x270 y538 w70 h22 +Border")
addExtBtn := mainGui.AddButton("x345 y538 w80 h24", "Add Ext")

settingsExitBtn := mainGui.AddButton("x295 y630 w185 h30", "Exit Program")
textColorPreview.SetFont("s11 " . "c" . SubStr(textColorCfg, 3))
for c in mainGui
    try c.Opt("Background" . SubStr(bgColorCfg, 3))

; Event wiring
lbLauncher.OnEvent("Change", LauncherGameSelected)
lbLauncher.OnEvent("DoubleClick", LaunchSelectedGame)
launchBtn.OnEvent("Click", LaunchSelectedGame)
launcherOpenFolderBtn.OnEvent("Click", (*) => Run(profileDir))
launcherLaunchEditorBtn.OnEvent("Click", LaunchDeviceGuiEditor)
launcherExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)

lbProfiles.OnEvent("Change", ProfileSelected)
lbProfiles.OnEvent("DoubleClick", ImportSelectedProfile)
profilesImportBtn.OnEvent("Click", ImportSelectedProfile)
profilesOpenFolderBtn.OnEvent("Click", (*) => Run(profileDir))
profilesBackupBtn.OnEvent("Click", BackupSelectedProfile)
profilesSetFolderBtn.OnEvent("Click", SelectProfilesFolder)
profilesLaunchEditorBtn.OnEvent("Click", LaunchDeviceGuiEditor)
profilesExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)

lbGames.OnEvent("Change", PopulateGameFields)
editorAddBtn.OnEvent("Click", AddOrUpdateGame)
editorRemoveBtn.OnEvent("Click", RemoveSelectedGame)
editorCreateShortcutBtn.OnEvent("Click", CreateGameShortcut)
editorClearBtn.OnEvent("Click", ClearEditorFields)
editorOpenFolderBtn.OnEvent("Click", (*) => Run(profileDir))
editorExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)
editorBrowseExeBtn.OnEvent("Click", BrowseGameExe)
editorOpenExeFolderBtn.OnEvent("Click", OpenExeFolder)
editorBrowseProfileBtn.OnEvent("Click", BrowseProfileFile)
openProfileFolderBtn.OnEvent("Click", (*) => Run(profileDir))
bgColorBtn.OnEvent("Click", PickBackgroundColor)
gamesSortDrop.OnEvent("Change", SortSettingsChanged)
orderSortDrop.OnEvent("Change", SortSettingsChanged)

; Devices / profile extensions
devicesDrop.OnEvent("Change", DeviceSelectionChanged)
profileExtDrop.OnEvent("Change", ProfileExtChanged)
addDeviceBtn.OnEvent("Click", AddNewDevice)
deleteDeviceBtn.OnEvent("Click", DeleteSelectedDevice)
addExtBtn.OnEvent("Click", AddExtensionToDevice)

launchEditorBtn.OnEvent("Click", LaunchDeviceGuiEditor)
captureImportBtn.OnEvent("Click", (*) => CaptureImportButtonCoords())
testImportBtn.OnEvent("Click", TestImportClick)
openProfilesBtn.OnEvent("Click", (*) => Run(A_ScriptDir))
selectDeviceGuiExeBtn.OnEvent("Click", SelectDeviceGuiExe)
settingsExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)

launcherSearchEdit.OnEvent("Change", FilterLauncherList)
profilesSearchEdit.OnEvent("Change", FilterProfilesList)
editorSearchEdit.OnEvent("Change", FilterGamesList)
launcherNotesEdit.OnEvent("Focus", LauncherNotesEditFocused)
launcherNotesEdit.OnEvent("LoseFocus", SaveLauncherNotes)
profilesNotesEdit.OnEvent("Focus", ProfilesNotesEditFocused)
profilesNotesEdit.OnEvent("LoseFocus", SaveProfileNotes)
tabs.OnEvent("Change", TabChanged)
TabChanged(*) {
    ; When switching to Game Launcher tab (tab 1), refresh with latest data
    if (tabs.Value = 1) {
        ; Reload games from INI file to get latest timestamps
        LoadGames()
        PopulateGameListControls()
    }
    ; When switching to Profile Manager tab (tab 2), refresh profiles
    else if (tabs.Value = 2) {
        PopulateProfileList()
    }
}

LauncherNotesEditFocused(*) {
    global current_notes_game, lbLauncher
    current_notes_game := lbLauncher.Text
}

ProfilesNotesEditFocused(*) {
    global current_notes_profile, lbProfiles
    current_notes_profile := lbProfiles.Text
}

AddOrUpdateGame(*) {
    global gameNameEdit, gameExeEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, games, closeManagerCheckbox, guiCloseDelayEdit, gamesFile, defaultProfileDelay
    localGameName := Trim(gameNameEdit.Value)
    exe := Trim(gameExeEdit.Value)
    prof := Trim(gameProfileEdit.Value)
    delay := Trim(gameDelayEdit.Value)
    launch := launchExeCheckbox.Value
    closeManager := closeManagerCheckbox.Value
    
    if (localGameName = "") {
        MsgBox("Game name cannot be empty.")
        return
    }
    
    added := (!games.Has(localGameName)) ? CurrentIsoTimestamp() : games[localGameName]["Added"]
    SaveGameToIni(localGameName, exe, prof, delay, launch, added, "", "", closeManager)
    
    ; Save the GUI close delay
    guiCloseDelay := Trim(guiCloseDelayEdit.Value)
    if (guiCloseDelay = "" || !RegExMatch(guiCloseDelay, "^\d+$")) {
        guiCloseDelay := defaultProfileDelay
    }
    IniWrite(guiCloseDelay, gamesFile, "Games", localGameName . ".GuiCloseDelay")
    
    LoadGames()
    PopulateGameListControls()
    PopulateProfileList()
    MsgBox("Game saved.")
}

RemoveSelectedGame(*) {
    global lbGames, games, gamesFile
    localGameName := lbGames.Text
    if (localGameName = "") {
        MsgBox("No game selected.")
        return
    }
    RemoveGameFromIni(localGameName)
    ; Also remove GUI close delay if it exists
    IniDelete(gamesFile, "Games", localGameName . ".GuiCloseDelay")
    LoadGames()
    PopulateGameListControls()
    MsgBox("Game removed.")
}

BackupSelectedProfile(*) {
    global lbProfiles, profileDir, backupDir
    localProfileName := lbProfiles.Text
    if (localProfileName = "") {
        MsgBox("No profile selected.")
        return
    }
    src := profileDir . "\" . localProfileName
    dest := backupDir . "\" . localProfileName
    if !DirExist(backupDir)
        DirCreate(backupDir)
    FileCopy(src, dest, 1)
    MsgBox("Profile backed up.")
}

BrowseGameExe(*) {
    global gameExeEdit, gameNameEdit, lastExeDir, gamesFile
    chosen := FileSelect(3, lastExeDir, "Select Game EXE", "Executables (*.exe)")
    if (chosen != "") {
        gameExeEdit.Value := chosen
        SplitPath(chosen, , &dir, , &outNameNoExt)
        gameNameEdit.Value := StrTitle(outNameNoExt)
        IniWrite(dir, gamesFile, "Config", "LastExeDir")
        lastExeDir := dir
    }
}

BrowseProfileFile(*) {
    global gameProfileEdit, profileDir, currentProfileExtension
    filter := (currentProfileExtension = "*" || currentProfileExtension = "")
        ? "All Files (*.*)"
        : "Profiles (*." . currentProfileExtension . ")"
    chosen := FileSelect(3, profileDir, "Select Profile File", filter)
    if (chosen != "")
        gameProfileEdit.Value := chosen
}

OpenExeFolder(*) {
    global gameExeEdit
    exe := gameExeEdit.Value
    if (exe = "")
        return
    SplitPath(exe, &outFile, &dir)
    Run(dir)
}

CreateGameShortcut(*) {
    global lbGames, games
    localGameName := lbGames.Text
    if (localGameName = "") {
        MsgBox("No game selected.")
        return
    }
    exe := games[localGameName]["Exe"]
    if (exe = "") {
        MsgBox("No EXE set for this game.")
        return
    }
    shortcutPath := FileSelect("S", A_Desktop . "\" . localGameName . ".lnk", "Save Shortcut As", "Shortcuts (*.lnk)")
    if (shortcutPath = "")
        return
    ahkPath := A_ScriptFullPath
    shortcut := ComObject("WScript.Shell").CreateShortcut(shortcutPath)
    shortcut.TargetPath := ahkPath
    shortcut.Arguments := "/launch `"" . localGameName . "`""
    shortcut.WorkingDirectory := A_ScriptDir
    shortcut.IconLocation := exe . ",0"
    shortcut.Save()
    MsgBox("Shortcut created at: " . shortcutPath)
}

LaunchSelectedGame(*) {
    global lbLauncher, games
    localGameName := lbLauncher.Text
    if (localGameName = "") {
        MsgBox("No game selected.")
        return
    }
    
    ; Launch the game - LaunchGameByName will update the timestamp
    LaunchGameByName(localGameName)
    
}

ImportSelectedProfile(*) {
    global lbProfiles, profileDir, games, gamesFile, defaultProfileDelay
    localProfileName := lbProfiles.Text
    if (localProfileName != "") {
        ; Try to find if this profile belongs to any game
        LoadGames()
        guiCloseDelay := defaultProfileDelay
        profilePath := profileDir . "\" . localProfileName
        
        for gameName, gameData in games {
            if (gameData["Profiles"] = profilePath) {
                ; Found the game that uses this profile
                guiCloseDelay := IniRead(gamesFile, "Games", gameName . ".GuiCloseDelay", defaultProfileDelay)
                break
            }
        }
        
        ImportProfile(profilePath, guiCloseDelay)  ; ← PASS THE DELAY
    }
    else
        MsgBox("No profile selected.")
}

PickBackgroundColor(*) {
    global mainGui, gamesFile, bgColorCfg, textColorCfg, textColorPreview
    pickedColor := PickColorFromDialog(bgColorCfg)
    if !pickedColor
        return
    bgColorCfg := pickedColor
    cr := ContrastRatio(SubStr(textColorCfg, 3), SubStr(bgColorCfg, 3))
    if (cr < 4.0)
        textColorCfg := PickBestTextColor(bgColorCfg)
    mainGui.BackColor := bgColorCfg
    ApplyTextColor(textColorCfg)
    for ctrlItem in mainGui
        try ctrlItem.Opt("Background" . SubStr(bgColorCfg, 3))
    textColorPreview.SetFont("s11 " . "c" . SubStr(textColorCfg, 3))
    IniWrite(bgColorCfg, gamesFile, "Theme", "BgColor")
    IniWrite(textColorCfg, gamesFile, "Theme", "TextColor")
}

SortSettingsChanged(*) {
    global gamesFile, gamesSortDrop, orderSortDrop, sortGamesMode, sortOrder
    
    sortGamesMode := gamesSortDrop.Text
    sortOrder := orderSortDrop.Text
    IniWrite(sortGamesMode, gamesFile, "Sort", "Games")
    IniWrite(sortOrder, gamesFile, "Sort", "Order")
    
    ; This should refresh the list with new sorting
    PopulateGameListControls()
    PopulateProfileList()
}

ProfileExtChanged(*) {
    global profileExtDrop, selectedDevice, deviceExtensions, deviceCurrentExt, currentProfileExtension
    if (selectedDevice = "")
        return
    label := profileExtDrop.Text
    if (label = "" || label = "* (All)") {
        currentProfileExtension := "*"
        deviceCurrentExt[selectedDevice] := "*"
    } else {
        if (SubStr(label, 1, 1) = ".")
            ext := SubStr(label, 2)
        else
            ext := label
        currentProfileExtension := ext
        deviceCurrentExt[selectedDevice] := ext
    }
    SaveDeviceExtensionsToIni()
    PopulateProfileList()
}

SelectDeviceGuiExe(*) {
    global deviceGuiExe, gamesFile
    chosen := FileSelect(3, , "Select Device GUI EXE", "Executables (*.exe)")
    if (chosen != "") {
        deviceGuiExe := chosen
        IniWrite(deviceGuiExe, gamesFile, "Config", "DeviceGuiExe")
        MsgBox("Device GUI EXE updated to:`n" . deviceGuiExe, "Success", "Iconi")
    }
}

SelectProfilesFolder(*) {
    global profileDir, gamesFile
    selectedFolder := DirSelect("*" . profileDir, 3, "Choose the folder where your profile files are stored")
    if (selectedFolder = "")
        return
    profileDir := selectedFolder
    IniWrite(profileDir, gamesFile, "Config", "ProfilesDir")
    MsgBox("Profiles folder set to:`n" . profileDir, "Profiles Folder Updated", "Iconi")
    PopulateProfileList()
}

ExitWithDeviceGuiClose(*) {
    global mainGui, gamesFile, tabs
    WinGetPos(&x, &y, , , mainGui.Hwnd)
    IniWrite(x, gamesFile, "Config", "WinX")
    IniWrite(y, gamesFile, "Config", "WinY")
    IniWrite(tabs.Value, gamesFile, "Config", "LastTab")
    processName := "DeviceGui.exe"
    if WinExist("ahk_exe " . processName)
        WinClose("ahk_exe " . processName)
    ExitApp
}

PopulateGameFields(*) {
    global lbGames, selGameLabel, gameNameEdit, gameExeEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, closeManagerCheckbox, guiCloseDelayEdit, games, gamesFile, defaultProfileDelay
    localGameName := lbGames.Text
    selGameLabel.Text := (localGameName = "") ? "" : "Selected: " . localGameName
    if (localGameName = "") {
        gameNameEdit.Value := ""
        gameExeEdit.Value := ""
        gameProfileEdit.Value := ""
        gameDelayEdit.Value := ""
        launchExeCheckbox.Value := 1
        closeManagerCheckbox.Value := 1
        guiCloseDelayEdit.Value := defaultProfileDelay  ; ← RESET TO DEFAULT
        return
    }
    data := games[localGameName]
    gameNameEdit.Value := localGameName
    gameExeEdit.Value := data["Exe"]
    gameProfileEdit.Value := data["Profiles"]
    gameDelayEdit.Value := data["PostImportDelay"]
    launchExeCheckbox.Value := data["LaunchExe"]
    closeManagerCheckbox.Value := data.Has("CloseManager") ? data["CloseManager"] : 1
    
    ; Set GUI close delay value
    guiCloseDelay := IniRead(gamesFile, "Games", localGameName . ".GuiCloseDelay", defaultProfileDelay)
    guiCloseDelayEdit.Value := guiCloseDelay
}

LauncherGameSelected(*) {
    global lbLauncher, launcherSelLabel, launcherNotesEdit, games, profiles
    localGameName := lbLauncher.Text
    launcherSelLabel.Text := (localGameName = "") ? "" : "Selected: " . localGameName
    profilePath := (localGameName = "") ? "" : games[localGameName]["Profiles"]
    if (profilePath != "") {
        profileName := RegExReplace(profilePath, ".*\\", "")
        launcherNotesEdit.Value := profiles.Has(profileName) ? profiles[profileName]["Notes"] : ""
    } else {
        launcherNotesEdit.Value := ""
    }
}

ProfileSelected(*) {
    global lbProfiles, profileSelLabel, profilesNotesEdit, profiles
    localProfileName := lbProfiles.Text
    profileSelLabel.Text := (localProfileName = "") ? "" : "Selected: " . localProfileName
    profilesNotesEdit.Value := (localProfileName = "") ? "" : (profiles.Has(localProfileName) ? profiles[localProfileName]["Notes"] : "")
}

SaveLauncherNotes(*) {
    global launcherNotesEdit, current_notes_game, games, profiles, gamesFile
    if (current_notes_game = "")
        return
    profilePath := games[current_notes_game]["Profiles"]
    if (profilePath = "")
        return
    profileName := RegExReplace(profilePath, ".*\\", "")
    notes := Trim(launcherNotesEdit.Value)
    IniWrite(notes, gamesFile, "Profiles", profileName . ".Notes")
    if !profiles.Has(profileName)
        profiles[profileName] := Map("Notes", notes)
    else
        profiles[profileName]["Notes"] := notes
    current_notes_game := ""
}

SaveProfileNotes(*) {
    global profilesNotesEdit, current_notes_profile, profiles, gamesFile
    if (current_notes_profile = "")
        return
    notes := Trim(profilesNotesEdit.Value)
    IniWrite(notes, gamesFile, "Profiles", current_notes_profile . ".Notes")
    if !profiles.Has(current_notes_profile)
        profiles[current_notes_profile] := Map("Notes", notes)
    else
        profiles[current_notes_profile]["Notes"] := notes
    current_notes_profile := ""
}

PopulateGameListControls() {
    global lbLauncher, lbGames, games, sortGamesMode, sortOrder, fullGameNames
    
    ; CRITICAL: Reload games from INI to get latest timestamps
    LoadGames()
    
    ; Save current selections
    selectedLauncher := lbLauncher.Text
    selectedEditor := lbGames.Text
    
    ; Clear lists
    lbLauncher.Delete()
    lbGames.Delete()
    
    ; Get sorted names with FRESH data
    fullGameNames := SortGameNames(games, sortGamesMode, sortOrder)
    
    ; Populate lists
    for gameName in fullGameNames {
        lbLauncher.Add([gameName])
        lbGames.Add([gameName])
    }
    
    ; Restore selections if possible - FIXED FOR AHK v2
    if (selectedLauncher != "") {
        ; In AHK v2, we need to manually find the item
        idx := 0
        for index, gameItem in fullGameNames {
            if (gameItem = selectedLauncher) {
                idx := index
                break
            }
        }
        if (idx > 0)
            lbLauncher.Choose(idx)
    }
    if (selectedEditor != "") {
        idx := 0
        for index, gameItem in fullGameNames {
            if (gameItem = selectedEditor) {
                idx := index
                break
            }
        }
        if (idx > 0)
            lbGames.Choose(idx)
    }
}

PopulateProfileList() {
    global lbProfiles, profileDir, sortProfilesMode, sortOrder, fullProfileNames
    lbProfiles.Delete()
    fullProfileNames := SortProfileNames(profileDir, sortProfilesMode, sortOrder)
    for v in fullProfileNames
        lbProfiles.Add([v])
}

FilterLauncherList(*) {
    global lbLauncher, fullGameNames, launcherSearchEdit
    FilterList(lbLauncher, fullGameNames, launcherSearchEdit.Value)
}

FilterGamesList(*) {
    global lbGames, fullGameNames, editorSearchEdit
    FilterList(lbGames, fullGameNames, editorSearchEdit.Value)
}

FilterProfilesList(*) {
    global lbProfiles, fullProfileNames, profilesSearchEdit
    FilterList(lbProfiles, fullProfileNames, profilesSearchEdit.Value)
}

FilterList(lb, fullList, searchText) {
    lb.Delete()
    searchLower := StrLower(searchText)
    for item in fullList {
        if (searchText = "" || InStr(StrLower(item), searchLower))
            lb.Add([item])
    }
}

ClearEditorFields(*) {
    global gameExeEdit, gameNameEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, lbGames, selGameLabel, closeManagerCheckbox, guiCloseDelayEdit, defaultProfileDelay
    gameExeEdit.Value := ""
    gameNameEdit.Value := ""
    gameProfileEdit.Value := ""
    gameDelayEdit.Value := ""
    launchExeCheckbox.Value := 0
    closeManagerCheckbox.Value := 1
    guiCloseDelayEdit.Value := defaultProfileDelay  ; ← RESET TO DEFAULT
    lbGames.Choose(0)
    selGameLabel.Text := ""
}

; ===== Device / Extension System =====

LoadDevices() {
    global gamesFile, devices, selectedDevice
    devices := []
    if !FileExist(gamesFile)
        return
    try raw := IniRead(gamesFile, "Devices")
    catch
        raw := ""
    if (raw != "") {
        for line in StrSplit(raw, "`n", "`r") {
            line := Trim(line)
            if (line = "" || !InStr(line, "="))
                continue
            p := StrSplit(line, "=")
            devName := Trim(p[2])
            if (devName != "")
                devices.Push(devName)
        }
    }
    if (devices.Length = 0) {
        devName := "Default Device"
        devices.Push(devName)
        IniWrite(devName, gamesFile, "Devices", "Device1")
    }
    if (selectedDevice = "" || !DeviceExists(selectedDevice)) {
        selectedDevice := devices[1]
        IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")
    }
}

DeviceExists(name) {
    global devices
    for d in devices {
        if (d = name)
            return true
    }
    return false
}

LoadDeviceExtensions() {
    global gamesFile, devices, deviceExtensions, deviceCurrentExt, currentProfileExtension, selectedDevice
    deviceExtensions := Map()
    deviceCurrentExt := Map()
    if !FileExist(gamesFile)
        return

    try rawExt := IniRead(gamesFile, "DeviceExtensions")
    catch
        rawExt := ""
    if (rawExt != "") {
        for line in StrSplit(rawExt, "`n", "`r") {
            line := Trim(line)
            if (line = "" || !InStr(line, "="))
                continue
            p := StrSplit(line, "=")
            devName := Trim(p[1])
            extStr := Trim(p[2])
            extArr := []
            if (extStr != "") {
                for e in StrSplit(extStr, ",") {
                    e := Trim(e)
                    if (e != "")
                        extArr.Push(e)
                }
            }
            deviceExtensions[devName] := extArr
        }
    }

    try rawCur := IniRead(gamesFile, "DeviceCurrentExt")
    catch
        rawCur := ""
    if (rawCur != "") {
        for line in StrSplit(rawCur, "`n", "`r") {
            line := Trim(line)
            if (line = "" || !InStr(line, "="))
                continue
            p := StrSplit(line, "=")
            devName := Trim(p[1])
            curExt := Trim(p[2])
            if (curExt != "")
                deviceCurrentExt[devName] := curExt
        }
    }

    for devName in devices {
        if !deviceExtensions.Has(devName) {
            deviceExtensions[devName] := []
        }
        if !deviceCurrentExt.Has(devName) {
            if (deviceExtensions[devName].Length > 0)
                deviceCurrentExt[devName] := deviceExtensions[devName][1]
            else
                deviceCurrentExt[devName] := "*"
            IniWrite(deviceCurrentExt[devName], gamesFile, "DeviceCurrentExt", devName)
        }
    }

    if (selectedDevice != "" && deviceCurrentExt.Has(selectedDevice))
        currentProfileExtension := deviceCurrentExt[selectedDevice]
    else
        currentProfileExtension := "*"
}

SaveDeviceExtensionsToIni() {
    global gamesFile, deviceExtensions, deviceCurrentExt
    IniDelete(gamesFile, "DeviceExtensions")
    for devName, extArr in deviceExtensions {
        extStr := ""
        for e in extArr {
            if (extStr != "")
                extStr .= ","
            extStr .= e
        }
        IniWrite(extStr, gamesFile, "DeviceExtensions", devName)
    }
    IniDelete(gamesFile, "DeviceCurrentExt")
    for devName, curExt in deviceCurrentExt {
        IniWrite(curExt, gamesFile, "DeviceCurrentExt", devName)
    }
}

PopulateDevicesUi() {
    global devicesDrop, profileExtDrop, devices, selectedDevice, deviceExtensions, deviceCurrentExt, currentProfileExtension
    devicesDrop.Delete()
    for devName in devices {
    devicesDrop.Add([devName])
}

    if (selectedDevice != "") {
        idx := 0, i := 0
        for devName in devices {
            i++
            if (devName = selectedDevice) {
                idx := i
                break
            }
        }
        if (idx > 0)
            devicesDrop.Choose(idx)
    } else if (devices.Length > 0) {
        selectedDevice := devices[1]
        devicesDrop.Choose(1)
    }
    PopulateProfileExtDrop()
}

PopulateProfileExtDrop() {
    global profileExtDrop, selectedDevice, deviceExtensions, deviceCurrentExt, currentProfileExtension
    profileExtDrop.Delete()
    if (selectedDevice = "" || !deviceExtensions.Has(selectedDevice)) {
        currentProfileExtension := "*"
        return
    }
    extArr := deviceExtensions[selectedDevice]
    if (extArr.Length = 0) {
        currentProfileExtension := "*"
        profileExtDrop.Add(["* (All)"])
        profileExtDrop.Choose(1)
        return
    }
    curExt := deviceCurrentExt.Has(selectedDevice) ? deviceCurrentExt[selectedDevice] : extArr[1]
    idx := 0, i := 0
    for ext in extArr {
        i++
        label := "." . ext
        profileExtDrop.Add([label])
        if (ext = curExt)
            idx := i
    }
    if (idx = 0)
        idx := 1
    profileExtDrop.Choose(idx)
    currentProfileExtension := extArr[idx]
}

DeviceSelectionChanged(*) {
    global devicesDrop, selectedDevice, gamesFile, deviceCurrentExt, deviceExtensions, currentProfileExtension
    newDev := devicesDrop.Text
    if (newDev = "")
        return
    selectedDevice := newDev
    IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")
    if !deviceExtensions.Has(selectedDevice)
        deviceExtensions[selectedDevice] := []
    if !deviceCurrentExt.Has(selectedDevice) {
        if (deviceExtensions[selectedDevice].Length > 0)
            deviceCurrentExt[selectedDevice] := deviceExtensions[selectedDevice][1]
        else
            deviceCurrentExt[selectedDevice] := "*"
    }
    currentProfileExtension := deviceCurrentExt[selectedDevice]
    PopulateProfileExtDrop()
    PopulateProfileList()
}

AddNewDevice(*) {
    global gamesFile, devices, selectedDevice, deviceExtensions, deviceCurrentExt
    devName := InputBox("Enter new device name:", "Add New Device").Value
    devName := Trim(devName)
    if (devName = "")
        return
    if DeviceExists(devName) {
        MsgBox("A device with that name already exists.", "Duplicate Device", "Icon!")
        return
    }
    idx := devices.Length + 1
    IniWrite(devName, gamesFile, "Devices", "Device" . idx)
    devices.Push(devName)
    deviceExtensions[devName] := []
    deviceCurrentExt[devName] := "*"
    IniWrite("*", gamesFile, "DeviceCurrentExt", devName)
    selectedDevice := devName
    IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")
    PopulateDevicesUi()
    PopulateProfileList()
}

DeleteSelectedDevice(*) {
    global gamesFile, devices, selectedDevice, deviceExtensions, deviceCurrentExt
    if (selectedDevice = "") {
        MsgBox("No device selected.", "Delete Device", "Icon!")
        return
    }
    if (devices.Length = 1) {
        MsgBox("You must have at least one device.", "Delete Device", "Icon!")
        return
    }
    if (MsgBox("Delete device '" . selectedDevice . "'?", "Confirm Delete", "YesNo Icon!") != "Yes")
        return

    newDevices := []
    for d in devices {
        if (d != selectedDevice)
            newDevices.Push(d)
    }
    devices := newDevices

    IniDelete(gamesFile, "Devices")
    idx := 1
    for d in devices {
        IniWrite(d, gamesFile, "Devices", "Device" . idx)
        idx++
    }

    if (deviceExtensions.Has(selectedDevice))
        deviceExtensions.Delete(selectedDevice)
    if (deviceCurrentExt.Has(selectedDevice))
        deviceCurrentExt.Delete(selectedDevice)
    IniDelete(gamesFile, "DeviceExtensions", selectedDevice)
    IniDelete(gamesFile, "DeviceCurrentExt", selectedDevice)

    selectedDevice := (devices.Length > 0) ? devices[1] : ""
    IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")

    PopulateDevicesUi()
    PopulateProfileList()
}

AddExtensionToDevice(*) {
    global gamesFile, selectedDevice, deviceExtensions, deviceCurrentExt, addExtEdit
    if (selectedDevice = "") {
        MsgBox("No device selected.", "Add Extension", "Icon!")
        return
    }
    ext := Trim(addExtEdit.Value)
    if (SubStr(ext, 1, 1) = ".")
        ext := SubStr(ext, 2)
    if (StrLen(ext) != 3 || !RegExMatch(ext, "^[A-Za-z0-9]{3}$")) {
        MsgBox("Please enter a 3-character extension (letters/numbers).", "Invalid Extension", "Icon!")
        return
    }
    ext := StrLower(ext)
    arr := deviceExtensions.Has(selectedDevice) ? deviceExtensions[selectedDevice] : []
    for e in arr {
        if (StrLower(e) = ext) {
            MsgBox("That extension already exists for this device.", "Duplicate Extension", "Icon!")
            return
        }
    }
    arr.Push(ext)
    deviceExtensions[selectedDevice] := arr
    if (!deviceCurrentExt.Has(selectedDevice) || deviceCurrentExt[selectedDevice] = "*" || deviceCurrentExt[selectedDevice] = "") {
        deviceCurrentExt[selectedDevice] := ext
    }
    SaveDeviceExtensionsToIni()
    PopulateProfileExtDrop()
    PopulateProfileList()
}

; ===== Startup =====

LoadDevices()
LoadDeviceExtensions()
LoadGames()
RepairGamesIni()
LoadProfiles()
PopulateDevicesUi()
PopulateGameListControls()
PopulateProfileList()

winX := IniRead(gamesFile, "Config", "WinX", "")
winY := IniRead(gamesFile, "Config", "WinY", "")
if (winX != "" && winY != "")
    mainGui.Show("x" . winX . " y" . winY)
else
    mainGui.Show("Center")