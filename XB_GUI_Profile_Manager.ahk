#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All

; ============================================================
; Script Name : eXBonez GUI Profile Manager
; Version     : 1.5
; Author      : eXBonez
; Description : A program for importing hardware profiles
;               when there is no other way besides mouse.
;               Now with full device-specific settings support.
; Date        : 2026-01-04
; ============================================================

SetWorkingDir A_ScriptDir

; ===== CLI Launch Mode (Desktop Shortcut Support) =====
; This MUST be at the very beginning before any GUI code
if (A_Args.Length > 0 && A_Args[1] = "/launch") {
    ; We need to load basic INI settings first
    gamesFile := A_ScriptDir . "\games.ini"
    
    ; Initialize games.ini if it doesn't exist
    if !FileExist(gamesFile) {
        IniWrite("Default", gamesFile, "Config", "SelectedDevice")
        IniWrite("*", gamesFile, "Config", "SelectedExtension")
        IniWrite("1000", gamesFile, "Config", "DefaultProfileDelay")
        IniWrite("300", gamesFile, "Config", "ClickDelay")
        IniWrite("Default", gamesFile, "Devices", "1")
        IniWrite("*", gamesFile, "DeviceExtensions", "Default")
    }
    
    ; Load devices and games for CLI mode
    devices := []
    games := Map()
    
    ; Load devices
    try rawDevices := IniRead(gamesFile, "Devices")
    catch
        rawDevices := ""
    if (rawDevices != "") {
        for deviceLine in StrSplit(rawDevices, "`n", "`r") {
            deviceLine := Trim(deviceLine)
            if (deviceLine = "" || !InStr(deviceLine, "="))
                continue
            deviceParts := StrSplit(deviceLine, "=")
            tempDevName := Trim(deviceParts[2])
            if (tempDevName != "")
                devices.Push(tempDevName)
        }
    }
    if (devices.Length = 0) {
        devices.Push("Default")
    }
    
    ; Load games
    try rawGames := IniRead(gamesFile, "Games")
    catch
        rawGames := ""
    if (rawGames != "") {
        for gameLine in StrSplit(rawGames, "`n", "`r") {
            gameLine := Trim(gameLine)
            if (gameLine = "" || !InStr(gameLine, "="))
                continue
            gameParts := StrSplit(gameLine, "=")
            key := Trim(gameParts[1]), val := Trim(gameParts[2])
            if !InStr(key, ".")
                continue
            
            keyParts := StrSplit(key, ".")
            gameKey := RegExReplace(keyParts[1], "\s"), field := keyParts[2]
            
            if !games.Has(gameKey)
                games[gameKey] := Map("Exe","", "PostImportDelay",1500, "LaunchExe",1, "CloseManager",1, "Added","", "LastPlayed","", "LaunchCount",0)
            games[gameKey][field] := val
        }
    }
    
    if (A_Args.Length < 2) {
        ExitApp
    }

    cliGameName := A_Args[2]
    
    ; Check if a device was specified as third argument
    cliDevice := A_Args.Length >= 3 ? A_Args[3] : ""
    
    ; If no device specified in args, use "Default"
    if (cliDevice = "") {
        cliDevice := "Default"
    }
    
    ; Simple matching for game name
    foundGameName := ""
    for gameKey, ignore in games {
        ; Simple comparison - remove spaces/special chars and compare lowercase
        cleanName1 := StrLower(RegExReplace(gameKey, "[^\w]", ""))
        cleanName2 := StrLower(RegExReplace(cliGameName, "[^\w]", ""))
        if (cleanName1 = cleanName2) {
            foundGameName := gameKey
            break
        }
    }
    
    if (foundGameName = "") {
        ExitApp
    }
    
    ; Get profile for the specified device
    prof := ""
    if (cliDevice != "") {
        ; Try new format first
        prof := IniRead(gamesFile, "Games", foundGameName . ".Profile" . cliDevice, "")
        
        ; Try old format if not found
        if (prof = "") {
            oldKey := foundGameName . cliDevice . ".Profiles"
            prof := IniRead(gamesFile, "Games", oldKey, "")
        }
    }
    
    ; If no profile found for that device, try to find any device that has a profile
    if (prof = "") {
        for tempDevName in devices {
            prof := IniRead(gamesFile, "Games", foundGameName . ".Profile" . tempDevName, "")
            if (prof = "") {
                oldKey := foundGameName . tempDevName . ".Profiles"
                prof := IniRead(gamesFile, "Games", oldKey, "")
            }
            if (prof != "") {
                cliDevice := tempDevName
                break
            }
        }
    }
    
    ; Update LastPlayed + LaunchCount BEFORE launching
    now := FormatTime(A_Now, "yyyy-MM-dd'T'HH:mm:ss")
    launchCount := games[foundGameName]["LaunchCount"]
    if (launchCount = "")
        launchCount := 0
    launchCount++
    
    ; Save the updated info
    key := RegExReplace(foundGameName, "\s")
    IniWrite(games[foundGameName]["Exe"], gamesFile, "Games", key . ".Exe")
    if (cliDevice != "" && prof != "") {
        deviceProfileKey := key . ".Profile" . cliDevice
        IniWrite(prof, gamesFile, "Games", deviceProfileKey)
    }
    IniWrite(games[foundGameName]["PostImportDelay"], gamesFile, "Games", key . ".PostImportDelay")
    IniWrite(games[foundGameName]["LaunchExe"], gamesFile, "Games", key . ".LaunchExe")
    IniWrite(games[foundGameName].Has("CloseManager") ? games[foundGameName]["CloseManager"] : 1, gamesFile, "Games", key . ".CloseManager")
    IniWrite(now, gamesFile, "Games", key . ".LastPlayed")
    IniWrite(launchCount, gamesFile, "Games", key . ".LaunchCount")
    
    ; Launch the game with the specified device
    LaunchGameByNameCLI(foundGameName, cliDevice, prof, games, gamesFile)
    
    ExitApp
}

; ===== CLI Helper Function =====
LaunchGameByNameCLI(gameName, deviceName, profilePath, games, gamesFile) {
    ; Get game data
    local exe, delay, launch, closeManager, guiCloseDelay
    
    exe := games[gameName]["Exe"]
    delay := games[gameName]["PostImportDelay"]
    launch := games[gameName]["LaunchExe"]
    closeManager := games[gameName].Has("CloseManager") ? games[gameName]["CloseManager"] : 1
    guiCloseDelay := IniRead(gamesFile, "Games", gameName . ".GuiCloseDelay", 1000)  ; Added this line
    
    ; Import profile if we have one
    if (profilePath != "" && FileExist(profilePath)) {
        ; Pass guiCloseDelay to the import function
        ImportProfileCLI(profilePath, deviceName, gamesFile, guiCloseDelay)  ; Modified this line
    }
    
    ; Launch the game EXE if configured to do so
    if (launch = 1 && exe != "") {
        if (delay != "" && delay is integer)
            Sleep(delay)
        
        Run('cmd.exe /c timeout /t 1 /nobreak >nul & start "" "' . exe . '"', , "Hide")
        
        ; Close if configured to do so
        if (closeManager = 1) {
            Sleep(500)
            ExitApp
        }
    } else {
        ; Just exit if not launching EXE
        if (closeManager = 1) {
            Sleep(500)
            ExitApp
        }
    }
}

ImportProfileCLI(path, deviceName, gamesFile, customDelay := "") {  ; Added customDelay parameter
    ; Simplified import function for CLI mode
    local localDeviceExe, processName, clickCount, clickList, x, y, index, coords, btnX, btnY
    local clickDelay, currentClickDelay, delayToUse, minimizeGuiAfterImport  ; Added delayToUse
    
    ; Get device GUI EXE
    localDeviceExe := IniRead(gamesFile, "Device_" . deviceName, "DeviceGuiExe", "")
    
    if (localDeviceExe = "" || !FileExist(localDeviceExe)) {
        return
    }
    
    ; Extract process name
    processName := SubStr(localDeviceExe, InStr(localDeviceExe, "\",, -1) + 1)
    
    ; Launch GUI if not running
    if !ProcessExist(processName) {
        Run(localDeviceExe)
        Sleep(1500)
    }
    
    ; Check for multi-click coordinates
    clickCount := IniRead(gamesFile, "Device_" . deviceName, "ImportClickCount", 0)
    if (clickCount > 0) {
        clickList := []
        Loop clickCount {
            x := IniRead(gamesFile, "Device_" . deviceName, "ImportButtonX" A_Index, "")
            y := IniRead(gamesFile, "Device_" . deviceName, "ImportButtonY" A_Index, "")
            if (x = "" || y = "")
                break
            clickList.Push([x, y])
        }
    } else {
        ; Single click fallback
        btnX := IniRead(gamesFile, "Device_" . deviceName, "ImportButtonX", "")
        btnY := IniRead(gamesFile, "Device_" . deviceName, "ImportButtonY", "")
        if (btnX = "" || btnY = "")
            return
        clickList := [[btnX, btnY]]
    }
    
    ; Activate window
    if WinExist("ahk_exe " . processName)
        WinActivate("ahk_exe " . processName)
    else if WinExist("Device")
        WinActivate("Device")
    else if WinExist("GUI")
        WinActivate("GUI")
    else
        return
    
    Sleep(300)
    CoordMode("Mouse", "Screen")
    
    ; Get click delay
    clickDelay := IniRead(gamesFile, "Device_" . deviceName, "ClickDelay", "300")
    currentClickDelay := Integer(clickDelay)
    
    ; Perform clicks
    for index, coords in clickList {
        MouseMove(coords[1], coords[2], 10)
        Sleep(100)
        Click
        if (index < clickList.Length) {
            Sleep(currentClickDelay)
        }
    }
    
    ; Wait for file dialog
    WinWait("ahk_class #32770", "", 10)
    if !WinExist("ahk_class #32770") {
        return
    }
    
    ; Try to activate and interact with the file dialog
    try {
        WinActivate("ahk_class #32770")
        Sleep(600)
        ControlSetText(path, "Edit1", "ahk_class #32770")
        Sleep(300)
        Send("{Enter}")
        if WinExist("ahk_class #32770") {
        ControlClick("Button1", "ahk_class #32770", , "Left", 1, "NA")
    }
        Sleep(300)
    } catch as err {
        ; CLI mode fails silently
        return
    }
    
    ; Use custom delay if provided, otherwise default
    delayToUse := (customDelay != "") ? customDelay : 1000  ; Changed from fixed 1000
    Sleep(delayToUse)
    
    ; Check minimize setting
    minimizeGuiAfterImport := IniRead(gamesFile, "Config", "MinimizeGuiAfterImport", 0)
    
    ; Check if we should minimize instead of close (CLI mode - no message)
    if (minimizeGuiAfterImport = 1 && ProcessExist(processName)) {
              ; Minimize the GUI instead of closing it
            if WinExist("ahk_exe " . processName) {
                WinMinimize("ahk_exe " . processName)  ; REMOVED THE EXTRA " AT THE END
                MsgBox("Device GUI minimized.`n`nIt will stay running in the background.`nYou can close it manually from system tray if needed.", "GUI Minimized", "Iconi T1.5")
            }
    } else {
        ; GENTLE CLOSURE SEQUENCE for CLI mode
        if ProcessExist(processName) {
            if WinExist("ahk_exe " . processName) {
                WinClose("ahk_exe " . processName)
                Sleep(1000)
                
                if ProcessExist(processName) {
                    try {
                        if WinExist("ahk_exe " . processName) {
                            WinActivate("ahk_exe " . processName)
                            Sleep(100)
                            Send("!{F4}")
                            Sleep(1000)
                        }
                    }
                    
                    if ProcessExist(processName) {
                        ProcessClose(processName)
                    }
                }
            } else {
                ProcessClose(processName)
            }
        }
    }
}

; ===== MAIN SCRIPT (GUI Mode) =====
gamesFile := A_ScriptDir . "\games.ini"

; ===== Default initialization if games.ini does NOT exist =====
if !FileExist(gamesFile) {
    ; Create minimal INI structure
    IniWrite("Default", gamesFile, "Config", "SelectedDevice")
    IniWrite("*", gamesFile, "Config", "SelectedExtension")
    IniWrite("1000", gamesFile, "Config", "DefaultProfileDelay")
    IniWrite("300", gamesFile, "Config", "ClickDelay")
    IniWrite("Default", gamesFile, "Devices", "1")
    IniWrite("*", gamesFile, "DeviceExtensions", "Default")
    
    ; Use Documents folder as default profile directory
    defaultProfilesDir := A_MyDocuments
    
    ; Create device-specific sections with defaults
    IniWrite("", gamesFile, "Device_Default", "DeviceGuiExe")
    IniWrite("300", gamesFile, "Device_Default", "ClickDelay")
    IniWrite(defaultProfilesDir, gamesFile, "Device_Default", "ProfileDir")
}

; Load global defaults
defaultProfileDelay := Integer(IniRead(gamesFile, "Config", "DefaultProfileDelay", "1000"))
clickDelayGlobal := Integer(IniRead(gamesFile, "Config", "ClickDelay", "300"))
profileDir := IniRead(gamesFile, "Config", "ProfilesDir", A_MyDocuments)
backupDir := A_ScriptDir . "\Backups"

bgColorCfg := IniRead(gamesFile, "Theme", "BgColor", "0xB0BEE3")
textColorCfg := IniRead(gamesFile, "Theme", "TextColor", "0x000000")
sortGamesMode := IniRead(gamesFile, "Sort", "Games", "Alphabetical")
sortProfilesMode := "Alphabetical"
sortOrder := IniRead(gamesFile, "Sort", "Order", "Ascending")
defaultProfile := IniRead(gamesFile, "Config", "DefaultProfile", "")
lastTab := IniRead(gamesFile, "Config", "LastTab", 1)
lastExeDir := IniRead(gamesFile, "Config", "LastExeDir", "")
trayMinimize := IniRead(gamesFile, "Config", "TrayMinimize", 1)
minimizeGuiAfterImport := IniRead(gamesFile, "Config", "MinimizeGuiAfterImport", 0)  ; Added this line

; Device / extension system
selectedDevice := IniRead(gamesFile, "Config", "SelectedDevice", "")
devices := []
deviceExtensions := Map()
deviceCurrentExt := Map()
deviceGuiExe := Map()
deviceClickDelay := Map()
deviceProfileDir := Map()
currentProfileExtension := "*"

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
    local requiredKeys, iniKey, defaultValue, currentValue
    
    requiredKeys := Map(
        "SelectedDevice", "Default",
        "SelectedExtension", "*",
        "DefaultProfileDelay", "1000",
        "ClickDelay", "300",
        "ProfilesDir", A_MyDocuments,
        "LastTab", "1"
    )
    
    for iniKey, defaultValue in requiredKeys {
        currentValue := IniRead(gamesFile, "Config", iniKey, "")
        if (currentValue = "") {
            IniWrite(defaultValue, gamesFile, "Config", iniKey)
        }
    }
}

CurrentIsoTimestamp() {
    return FormatTime(A_Now, "yyyy-MM-dd'T'HH:mm:ss")
}

GetBaseGameName(displayName) {
    return RegExReplace(displayName, "\s*\(.*\)$", "")
}

GetDeviceClickDelay(deviceName) {
    global gamesFile, deviceClickDelay, clickDelayGlobal
    local delay
    
    if (deviceClickDelay.Has(deviceName)) {
        return deviceClickDelay[deviceName]
    } else {
        delay := IniRead(gamesFile, "Device_" . deviceName, "ClickDelay", "")
        if (delay != "" && RegExMatch(delay, "^\d+$")) {
            deviceClickDelay[deviceName] := Integer(delay)
            return deviceClickDelay[deviceName]
        }
        return clickDelayGlobal
    }
}

GetDeviceProfileDir(deviceName) {
    global gamesFile, deviceProfileDir, profileDir
    local dir
    
    if (deviceProfileDir.Has(deviceName)) {
        return deviceProfileDir[deviceName]
    } else {
        dir := IniRead(gamesFile, "Device_" . deviceName, "ProfileDir", "")
        if (dir != "" && DirExist(dir)) {
            deviceProfileDir[deviceName] := dir
            return dir
        }
        return profileDir
    }
}

DeviceExists(name) {
    global devices
    local tempDev
    
    for tempDev in devices {
        if (tempDev = name)
            return true
    }
    return false
}

LoadDevices() {
    global gamesFile, devices, selectedDevice, deviceGuiExe, deviceClickDelay, deviceProfileDir, profileDir
    local rawDevices, deviceLine, deviceParts, tempDevName, dName, exePath, delay, dir
    
    devices := []
    deviceGuiExe := Map()
    deviceClickDelay := Map()
    deviceProfileDir := Map()
    
    if !FileExist(gamesFile)
        return
    
    ; Load device names
    try rawDevices := IniRead(gamesFile, "Devices")
    catch
        rawDevices := ""
    if (rawDevices != "") {
        for deviceLine in StrSplit(rawDevices, "`n", "`r") {
            deviceLine := Trim(deviceLine)
            if (deviceLine = "" || !InStr(deviceLine, "="))
                continue
            deviceParts := StrSplit(deviceLine, "=")
            tempDevName := Trim(deviceParts[2])
            if (tempDevName != "")
                devices.Push(tempDevName)
        }
    }
    if (devices.Length = 0) {
        tempDevName := "Default"
        devices.Push(tempDevName)
        IniWrite(tempDevName, gamesFile, "Devices", "Device1")
    }
    if (selectedDevice = "" || !DeviceExists(selectedDevice)) {
        selectedDevice := devices[1]
        IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")
    }
    
    ; Load device-specific settings
    for dName in devices {
        exePath := IniRead(gamesFile, "Device_" . dName, "DeviceGuiExe", "")
        if (exePath != "")
            deviceGuiExe[dName] := exePath
        
        delay := IniRead(gamesFile, "Device_" . dName, "ClickDelay", "")
        if (delay != "" && RegExMatch(delay, "^\d+$"))
            deviceClickDelay[dName] := Integer(delay)
        
        dir := IniRead(gamesFile, "Device_" . dName, "ProfileDir", "")
        if (dir != "" && DirExist(dir))
            deviceProfileDir[dName] := dir
    }
}

LoadDeviceExtensions() {
    global gamesFile, devices, deviceExtensions, deviceCurrentExt, currentProfileExtension, selectedDevice
    local rawExt, extLine, extParts, tempDev, extStr, e, extArr, rawCur, curLine, curParts, curExt
    
    deviceExtensions := Map()
    deviceCurrentExt := Map()
    if !FileExist(gamesFile)
        return

    try rawExt := IniRead(gamesFile, "DeviceExtensions")
    catch
        rawExt := ""
    if (rawExt != "") {
        for extLine in StrSplit(rawExt, "`n", "`r") {
            extLine := Trim(extLine)
            if (extLine = "" || !InStr(extLine, "="))
                continue
            extParts := StrSplit(extLine, "=")
            tempDev := Trim(extParts[1])
            extStr := Trim(extParts[2])
            extArr := []
            if (extStr != "") {
                for e in StrSplit(extStr, ",") {
                    e := Trim(e)
                    if (e != "")
                        extArr.Push(e)
                }
            }
            deviceExtensions[tempDev] := extArr
        }
    }

    try rawCur := IniRead(gamesFile, "DeviceCurrentExt")
    catch
        rawCur := ""
    if (rawCur != "") {
        for curLine in StrSplit(rawCur, "`n", "`r") {
            curLine := Trim(curLine)
            if (curLine = "" || !InStr(curLine, "="))
                continue
            curParts := StrSplit(curLine, "=")
            tempDev := Trim(curParts[1])
            curExt := Trim(curParts[2])
            if (curExt != "")
                deviceCurrentExt[tempDev] := curExt
        }
    }

    for tempDev in devices {
        if !deviceExtensions.Has(tempDev) {
            deviceExtensions[tempDev] := []
        }
        if !deviceCurrentExt.Has(tempDev) {
            if (deviceExtensions[tempDev].Length > 0)
                deviceCurrentExt[tempDev] := deviceExtensions[tempDev][1]
            else
                deviceCurrentExt[tempDev] := "*"
            IniWrite(deviceCurrentExt[tempDev], gamesFile, "DeviceCurrentExt", tempDev)
        }
    }

    if (selectedDevice != "" && deviceCurrentExt.Has(selectedDevice))
        currentProfileExtension := deviceCurrentExt[selectedDevice]
    else
        currentProfileExtension := "*"
}

SaveDeviceExtensionsToIni() {
    global gamesFile, deviceExtensions, deviceCurrentExt
    local loopDev, extArr, e, extStr, curExt
    
    IniDelete(gamesFile, "DeviceExtensions")
    for loopDev, extArr in deviceExtensions {
        extStr := ""
        for e in extArr {
            if (extStr != "")
                extStr .= ","
            extStr .= e
        }
        IniWrite(extStr, gamesFile, "DeviceExtensions", loopDev)
    }
    IniDelete(gamesFile, "DeviceCurrentExt")
    for loopDev, curExt in deviceCurrentExt {
        IniWrite(curExt, gamesFile, "DeviceCurrentExt", loopDev)
    }
}

ArrayReverse(arr) {
    local out
    out := []
    Loop arr.Length
        out.Push(arr[arr.Length + 1 - A_Index])
    return out
}

HexToRGB(hex) {
    local r, g, b
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
    local fg, bg, L1, L2, t
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
    local opt, ctrlItem
    opt := "c" . SubStr(textColor, 3)
    for ctrlItem in mainGui
        try ctrlItem.SetFont(opt)
}

PickColorFromDialog(start := "0xFFFFFF") {
    local colorGui, sR, sG, sB, preview, hexEdit, ok, revert, picked
    local r, g, b, initialR, initialG, initialB, initialHex
    local updateFromSliders, updateFromHex, revertToInitial
    
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
    
    updateFromSliders := (*) => (
        hex := "0x" . Format("{:02X}{:02X}{:02X}", sR.Value, sG.Value, sB.Value),
        preview.Opt("Background" . SubStr(hex, 3)),
        hexEdit.Value := hex
    )
    
    updateFromHex := (*) => (
        hex := Trim(hexEdit.Value),
        hex := RegExReplace(hex, "^0x|#", ""),
        (StrLen(hex) = 6 ? (
            r := "0x" . SubStr(hex, 1, 2),
            g := "0x" . SubStr(hex, 3, 2),
            b := "0x" . SubStr(hex, 5, 2),
            sR.Value := r,
            sG.Value := g,
            sB.Value := b,
            preview.Opt("Background" . hex)
        ) : 0)
    )
    
    revertToInitial := (*) => (
        sR.Value := initialR,
        sG.Value := initialG,
        sB.Value := initialB,
        hexEdit.Value := initialHex,
        preview.Opt("Background" . SubStr(initialHex, 3))
    )
    
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
    global gamesFile, games, selectedDevice, devices
    local gamesData, gLine, gParts, key, val, keyParts, gameKey, field, d, devName, baseGameKey, newKey
    
    games := Map()
    if !FileExist(gamesFile)
        return
    try gamesData := IniRead(gamesFile, "Games")
    catch
        return
    if (gamesData = "")
        return
    
    ; First, make sure devices are loaded
    LoadDevices()
    
    for gLine in StrSplit(gamesData, "`n", "`r") {
        gLine := Trim(gLine)
        if (gLine = "" || !InStr(gLine, "="))
            continue
        gParts := StrSplit(gLine, "=")
        key := Trim(gParts[1]), val := Trim(gParts[2])
        if !InStr(key, ".")
            continue
        keyParts := StrSplit(key, ".")
        gameKey := RegExReplace(keyParts[1], "\s"), field := keyParts[2]
        
        ; Handle OLD format: Windows_11M913-Max.Profiles
        if (field = "Profiles") {
            for d in devices {
                if (d != "Default" && SubStr(gameKey, -StrLen(d) + 1) = d) {
                    devName := d
                    baseGameKey := SubStr(gameKey, 1, StrLen(gameKey) - StrLen(devName))
                    gameKey := baseGameKey
                    field := "Profile_" . devName
                    
                    newKey := gameKey . ".Profile" . devName
                    IniWrite(val, gamesFile, "Games", newKey)
                    break
                }
            }
        }
        else if (InStr(field, "Profile")) {
            devName := StrReplace(field, "Profile")
            field := "Profile_" . devName
        }
        
        if !games.Has(gameKey)
            games[gameKey] := Map("Exe","", "PostImportDelay",1500, "LaunchExe",1, "CloseManager",1, "Added","", "LastPlayed","", "LaunchCount",0)
        games[gameKey][field] := val
    }
}

RepairGamesIni() {
    global gamesFile
    local gameData, gameLine, gameParts, key, val, game, correctKey, fixed

    try gameData := IniRead(gamesFile, "Games")
    catch
        return

    if (gameData = "")
        return

    fixed := false

    for gameLine in StrSplit(gameData, "`n", "`r") {
        gameLine := Trim(gameLine)
        if (gameLine = "" || !InStr(gameLine, "="))
            continue

        gameParts := StrSplit(gameLine, "=")
        key := Trim(gameParts[1])
        val := Trim(gameParts[2])

        if InStr(key, ".Profile") && !InStr(key, ".Profiles") {
            game := StrReplace(key, ".Profile")
            correctKey := game . ".Profiles"

            IniWrite(val, gamesFile, "Games", correctKey)
            IniDelete(gamesFile, "Games", key)
            fixed := true
        }
    }

    if (fixed) {
        LoadGames()
    }
}

LoadProfiles() {
    global gamesFile, profiles
    local rawProfiles, profileLine, profileParts, key, val, keyParts, profileKey, field
    
    profiles := Map()
    if !FileExist(gamesFile)
        return
    try rawProfiles := IniRead(gamesFile, "Profiles")
    catch
        return
    if (rawProfiles = "")
        return
    for profileLine in StrSplit(rawProfiles, "`n", "`r") {
        profileLine := Trim(profileLine)
        if (profileLine = "" || !InStr(profileLine, "="))
            continue
        profileParts := StrSplit(profileLine, "=")
        key := Trim(profileParts[1]), val := Trim(profileParts[2])
        if !InStr(key, ".")
            continue
        keyParts := StrSplit(key, ".")
        profileKey := keyParts[1], field := keyParts[2]
        if !profiles.Has(profileKey)
            profiles[profileKey] := Map("Notes","")
        profiles[profileKey][field] := val
    }
}

SaveGameToIni(gameName, exe, profs, delay, launch, added := "", last := "", count := "", closeManager := 1) {
    global gamesFile, selectedDevice
    local key, deviceProfileKey, oldKey
    
    key := RegExReplace(gameName, "\s")
    
    IniWrite(exe, gamesFile, "Games", key . ".Exe")
    
    if (selectedDevice != "" && profs != "") {
        deviceProfileKey := key . ".Profile" . selectedDevice
        IniWrite(profs, gamesFile, "Games", deviceProfileKey)
        
        oldKey := key . selectedDevice . ".Profiles"
        IniDelete(gamesFile, "Games", oldKey)
    }
    
    IniWrite(delay, gamesFile, "Games", key . ".PostImportDelay")
    IniWrite(launch, gamesFile, "Games", key . ".LaunchExe")
    IniWrite(closeManager, gamesFile, "Games", key . ".CloseManager")
    
    if (added != "")
        IniWrite(added, gamesFile, "Games", key . ".Added")
    if (last != "")
        IniWrite(last, gamesFile, "Games", key . ".LastPlayed")
    if (count != "")
        IniWrite(count, gamesFile, "Games", key . ".LaunchCount")
}

RemoveGameFromIni(gameName) {
    global gamesFile
    local f, gameEntries, gameLine, gameParts, key
    
    for f in ["Exe","Profiles","PostImportDelay","LaunchExe","Added","LastPlayed","LaunchCount"]
        IniDelete(gamesFile, "Games", gameName . "." . f)
    
    try gameEntries := IniRead(gamesFile, "Games")
    catch
        return
    
    if (gameEntries != "") {
        for gameLine in StrSplit(gameEntries, "`n", "`r") {
            gameLine := Trim(gameLine)
            if (gameLine = "" || !InStr(gameLine, "="))
                continue
            gameParts := StrSplit(gameLine, "=")
            key := Trim(gameParts[1])
            if (InStr(key, gameName . ".Profile") || InStr(key, gameName . "M913-")) {
                IniDelete(gamesFile, "Games", key)
            }
        }
    }
}

GetGamesForCurrentDevice() {
    global games, selectedDevice, gamesFile
    local filteredGames, gameName, gameData, deviceProfileKey, oldProfileKey, oldProfile, newKey
    
    filteredGames := Map()
    
    for gameName, gameData in games {
        deviceProfileKey := "Profile_" . selectedDevice
        if (gameData.Has(deviceProfileKey) && gameData[deviceProfileKey] != "") {
            filteredGames[gameName] := gameData.Clone()
        }
        else {
            oldProfileKey := gameName . selectedDevice . ".Profiles"
            try oldProfile := IniRead(gamesFile, "Games", oldProfileKey, "")
            if (oldProfile != "") {
                filteredGames[gameName] := gameData.Clone()
                newKey := gameName . ".Profile" . selectedDevice
                IniWrite(oldProfile, gamesFile, "Games", newKey)
            }
        }
    }
    
    return filteredGames
}

GetGameDisplayName(gameName) {
    global selectedDevice
    return gameName . " (" . selectedDevice . ")"
}

SortGameNames(gamesMap, mode, order) {
    local names, n, dummy, s, v, t, line, lineParts
    
    names := []
    For n, dummy in gamesMap
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
        s := ""
        for n in names {
            t := ""
            if (mode = "TimeAdded") {
                t := gamesMap[n]["Added"]
            } else if (mode = "LastPlayed") {
                t := gamesMap[n]["LastPlayed"]
            }
            
            if (t = "") {
                if (mode = "TimeAdded")
                    t := "9999-12-31T23:59:59"
                else if (mode = "LastPlayed")
                    t := "1900-01-01T00:00:00"
            }
            
            s .= t . "|" . n . "`n"
        }
        
        s := RTrim(s, "`n")
        s := Sort(s)
        
        names := []
        for line in StrSplit(s, "`n") {
            lineParts := StrSplit(line, "|")
            if (lineParts.Length >= 2)
                names.Push(lineParts[2])
        }
    }
    
    if (order = "Descending")
        names := ArrayReverse(names)
    
    return names
}

SortProfileNames(dir, mode, order) {
    global currentProfileExtension
    local items, pattern, s, v
    
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
        s := Sort(s)
        items := StrSplit(s, "`n")
    }
    if (order = "Descending")
        items := ArrayReverse(items)
    return items
}

CaptureImportButtonCoords() {
    global gamesFile, selectedDevice, deviceGuiExe, clickCaptureCount, clickCapturedList, overlay, clickDelayEdit
    local countGui, dd, ok

    countGui := Gui("+ToolWindow +AlwaysOnTop", "Click Count")
    countGui.SetFont("s11")
    countGui.AddText("x10 y10 w200", "How many clicks to record?")
    dd := countGui.AddDropDownList("x10 y40 w120", ["1","2","3","4","5","6","7","8","9","10"])
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
    global selectedDevice, deviceGuiExe, clickCaptureCount, overlay, clickCounterText, clickDelayEdit
    local currentDeviceGuiExe, processName, currentClickDelay

    currentDeviceGuiExe := deviceGuiExe.Has(selectedDevice) ? deviceGuiExe[selectedDevice] : ""
    
    if (currentDeviceGuiExe = "" || !FileExist(currentDeviceGuiExe)) {
        MsgBox("Device GUI EXE is not set or missing for device: " . selectedDevice)
        return
    }

    processName := SubStr(currentDeviceGuiExe, InStr(currentDeviceGuiExe, "\",, -1) + 1)

    Run(currentDeviceGuiExe)
    Sleep(1500)

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

    currentClickDelay := GetDeviceClickDelay(selectedDevice)
    
    overlay := Gui("-Caption +AlwaysOnTop +ToolWindow -Theme")
    overlay.SetFont("s11")
    overlay.BackColor := "0xEEAA99"
    overlay.Opt("+LastFound")
    WinSetTransparent(200)

    overlay.AddText("x10 y10 w320 h20 Center", "Click Counter:")
    clickCounterText := overlay.AddText("x10 y30 w320 h30 Center", clickCaptureCount . " clicks left")
    clickCounterText.SetFont("Bold")

    overlay.AddText("x10 y65 w320 h20 Center", "Delay between clicks: " . currentClickDelay . "ms")
    overlay.AddText("x10 y85 w320 h20", "Press F8 to capture each click")
    overlay.Show("Center w340 h110")

    Sleep(100)
    Hotkey("F8", MultiClickCapture_Fire, "On")
}

MultiClickCapture_Fire(*) {
    global clickCaptureCount, clickCapturedList, gamesFile, selectedDevice, overlay, clickCounterText, clickDelayEdit
    local x, y, clicksLeft, successOverlay, currentClickDelay, currentDeviceGuiExe, processName

    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)
    clickCapturedList.Push([x, y])

    clicksLeft := clickCaptureCount - clickCapturedList.Length
    if (clicksLeft > 0) {
        clickCounterText.Text := clicksLeft . " click" . (clicksLeft = 1 ? "" : "s") . " left"
        return
    }

    if (clickCapturedList.Length >= clickCaptureCount) {
        Hotkey("F8", "Off")

        IniWrite(clickCaptureCount, gamesFile, "Device_" . selectedDevice, "ImportClickCount")

        Loop clickCapturedList.Length {
            IniWrite(clickCapturedList[A_Index][1], gamesFile, "Device_" . selectedDevice, "ImportButtonX" A_Index)
            IniWrite(clickCapturedList[A_Index][2], gamesFile, "Device_" . selectedDevice, "ImportButtonY" A_Index)
        }

        if (clickCapturedList.Length >= 1) {
            IniWrite(clickCapturedList[1][1], gamesFile, "Device_" . selectedDevice, "ImportButtonX")
            IniWrite(clickCapturedList[1][2], gamesFile, "Device_" . selectedDevice, "ImportButtonY")
        }

        if (overlay) {
            overlay.Destroy()
        }

        currentClickDelay := GetDeviceClickDelay(selectedDevice)
        
        successOverlay := Gui("-Caption +AlwaysOnTop +ToolWindow -Theme")
        successOverlay.SetFont("s11 Bold")
        successOverlay.BackColor := "0x90EE90"
        successOverlay.Opt("+LastFound")
        WinSetTransparent(220)

        successOverlay.AddText("x10 y10 w320 h40 Center cGreen", "✓ Recording Success!")
        successOverlay.AddText("x10 y50 w320 h30 Center", "Saved " . clickCaptureCount . " click(s)")
        successOverlay.AddText("x10 y80 w320 h30 Center", "Click delay: " . currentClickDelay . "ms")
        successOverlay.Show("Center w340 h120")

        Sleep(3000)

        successOverlay.Destroy()

        currentDeviceGuiExe := deviceGuiExe.Has(selectedDevice) ? deviceGuiExe[selectedDevice] : ""
        if (currentDeviceGuiExe != "") {
            processName := SubStr(currentDeviceGuiExe, InStr(currentDeviceGuiExe, "\",, -1) + 1)
            if ProcessExist(processName) {
                ProcessClose(processName)
            }
        }
    }
}

TestImportClick(*) {
    global gamesFile, selectedDevice, deviceGuiExe
    local currentDeviceGuiExe, processName, clickCount, clickList, x, y, index, coords, currentClickDelay

    currentDeviceGuiExe := deviceGuiExe.Has(selectedDevice) ? deviceGuiExe[selectedDevice] : ""
    
    if (currentDeviceGuiExe = "" || !FileExist(currentDeviceGuiExe)) {
        MsgBox("Device GUI EXE is not set or missing for device: " . selectedDevice)
        return
    }

    processName := SubStr(currentDeviceGuiExe, InStr(currentDeviceGuiExe, "\",, -1) + 1)

    clickCount := IniRead(gamesFile, "Device_" . selectedDevice, "ImportClickCount", 0)
    if (clickCount = 0) {
        MsgBox("No captured clicks found for device: " . selectedDevice . "`nRun 'Capture Import Button' first.", "No Clicks Found", "Icon! T1.5")
        return
    }

    clickList := []
    Loop clickCount {
        x := IniRead(gamesFile, "Device_" . selectedDevice, "ImportButtonX" A_Index, "")
        y := IniRead(gamesFile, "Device_" . selectedDevice, "ImportButtonY" A_Index, "")
        if (x = "" || y = "")
            break
        clickList.Push([x, y])
    }

    if (clickList.Length = 0) {
        MsgBox("No valid click coordinates found for device: " . selectedDevice)
        return
    }

    Run(currentDeviceGuiExe)
    Sleep(1000)

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

    currentClickDelay := GetDeviceClickDelay(selectedDevice)
    
    for index, coords in clickList {
        MouseMove(coords[1], coords[2], 10)
        Sleep(200)
        Click
        if (index < clickList.Length) {
            Sleep(currentClickDelay)
        }
    }

    Sleep(1000)

    if ProcessExist(processName)
        ProcessClose(processName)
}

ImportProfile(path, customDelay := "") {
    global selectedDevice, deviceGuiExe, gamesFile, defaultProfileDelay, minimizeGuiAfterImport
    local currentDeviceGuiExe, clickCount, clickList, x, y, btnX, btnY, processName, index, coords
    local currentClickDelay, delayToUse
    
    currentDeviceGuiExe := deviceGuiExe.Has(selectedDevice) ? deviceGuiExe[selectedDevice] : ""
    
    if (currentDeviceGuiExe = "") {
        MsgBox("Device GUI EXE is not set for device: " . selectedDevice . "`nPlease select it in Settings.", "Error", "Iconx T1.5")
        return
    }
    if !FileExist(currentDeviceGuiExe) {
        MsgBox("Device GUI software not found at:`n" . currentDeviceGuiExe, "Error", "Iconx T1.5")
        return
    }
    if !FileExist(path) {
        MsgBox("Profile file not found.")
        return
    }
    
    clickCount := IniRead(gamesFile, "Device_" . selectedDevice, "ImportClickCount", 0)
    if (clickCount > 0) {
        clickList := []
        Loop clickCount {
            x := IniRead(gamesFile, "Device_" . selectedDevice, "ImportButtonX" A_Index, "")
            y := IniRead(gamesFile, "Device_" . selectedDevice, "ImportButtonY" A_Index, "")
            if (x = "" || y = "")
                break
            clickList.Push([x, y])
        }
        
        if (clickList.Length = 0) {
            MsgBox("No valid multi-click coordinates found for device: " . selectedDevice, "Error", "Iconx T1.5")
            return
        }
    } else {
        btnX := IniRead(gamesFile, "Device_" . selectedDevice, "ImportButtonX", "")
        btnY := IniRead(gamesFile, "Device_" . selectedDevice, "ImportButtonY", "")
        if (btnX = "" || btnY = "") {
            MsgBox("Import button coordinates not set for device: " . selectedDevice, "Error", "Iconx T1.5")
            return
        }
        clickList := [[btnX, btnY]]
    }
    
    processName := ""
    if (currentDeviceGuiExe != "")
        processName := SubStr(currentDeviceGuiExe, InStr(currentDeviceGuiExe, "\",, -1) + 1)
    
    if !ProcessExist(processName) {
        Run(currentDeviceGuiExe)
        Sleep(1500)
    }
    
    if !(WinWait("ahk_exe " . processName, "", 5)
        || WinWait("Device", "", 5)
        || WinWait("GUI", "", 5)) 
    {
        MsgBox("Could not find Device GUI window.")
        return
    }
    
    if WinExist("ahk_exe " . processName)
        WinActivate("ahk_exe " . processName)
    else if WinExist("Device")
        WinActivate("Device")
    else if WinExist("GUI")
        WinActivate("GUI")
    
    Sleep(300)
    CoordMode("Mouse", "Screen")
    
    currentClickDelay := GetDeviceClickDelay(selectedDevice)
    
    for index, coords in clickList {
        MouseMove(coords[1], coords[2], 10)
        Sleep(100)
        Click
        if (index < clickList.Length) {
            Sleep(currentClickDelay)
        }
    }
    
    ; Wait for file dialog with timeout
    if !WinWait("ahk_class #32770", "", 5) {
        MsgBox("File open dialog did not appear.`n`nPossible issues:`n- Device GUI is not responding`n- Import button coordinates may be incorrect`n- Device software may need to be restarted", "GUI Not Loaded Properly", "Iconx T2.5")
        return
    }
    
    ; Try to activate and interact with the file dialog
    try {
        WinActivate("ahk_class #32770")
        Sleep(600)
        
        ControlSetText(path, "Edit1", "ahk_class #32770")
        Sleep(300)
        Send("{Enter}")
        Sleep(300)

    ; If dialog is still open, click Button1 as fallback
        if WinExist("ahk_class #32770") {
        ControlClick("Button1", "ahk_class #32770", , "Left", 1, "NA")
    }
        Sleep(500)

    } catch as err {
        MsgBox("Device GUI is not loaded properly.`n`nPlease check:`n- Device is connected`n- Device software is running correctly`n- File dialog is visible", "GUI Not Ready", "Iconx T2.5")
        return
    }
    
    delayToUse := (customDelay != "") ? customDelay : defaultProfileDelay
    Sleep(delayToUse)
    
    ; Check if we should minimize instead of close
    if (minimizeGuiAfterImport = 1 && ProcessExist(processName)) {
        ; Minimize the GUI instead of closing it
        if WinExist("ahk_exe " . processName) {
            WinMinimize("ahk_exe " . processName)
            MsgBox("Device GUI minimized.`n`nIt will stay running in the background.`nYou can close it manually from system tray if needed.", "GUI Minimized", "Iconi T2")
        }
    } else {
        ; GENTLE CLOSURE SEQUENCE - Try softer methods before force closing
        if ProcessExist(processName) {
            ; Method 1: Try closing window normally
            if WinExist("ahk_exe " . processName) {
                WinClose("ahk_exe " . processName)
                Sleep(1000)  ; Give it time to close gracefully
                
                ; Check if it's still running
                if ProcessExist(processName) {
                    ; Method 2: Send Alt+F4
                    try {
                        if WinExist("ahk_exe " . processName) {
                            WinActivate("ahk_exe " . processName)
                            Sleep(100)
                            Send("!{F4}")
                            Sleep(1000)
                        }
                    }
                    
                    ; Method 3: Only force close if still running
                    if ProcessExist(processName) {
                        ; Last resort: Force close
                        ProcessClose(processName)
                    }
                }
            } else {
                ; Window doesn't exist but process does - just force close
                ProcessClose(processName)
            }
        }
    }
}

GetGameProfileForDevice(gameName, deviceName) {
    global gamesFile
    local deviceProfile, oldKey, newKey
    
    if (deviceName = "")
        return ""
    
    deviceProfile := IniRead(gamesFile, "Games", gameName . ".Profile" . deviceName, "")
    
    if (deviceProfile = "") {
        oldKey := gameName . deviceName . ".Profiles"
        deviceProfile := IniRead(gamesFile, "Games", oldKey, "")
        
        if (deviceProfile != "") {
            newKey := gameName . ".Profile" . deviceName
            IniWrite(deviceProfile, gamesFile, "Games", newKey)
        }
    }
    
    return deviceProfile
}

LaunchDeviceGuiEditor(*) {
    global selectedDevice, deviceGuiExe
    local currentDeviceGuiExe
    
    currentDeviceGuiExe := deviceGuiExe.Has(selectedDevice) ? deviceGuiExe[selectedDevice] : ""
    
    if (currentDeviceGuiExe = "") {
        MsgBox(
            "Device GUI EXE is not set for device: " . selectedDevice . "`n`n"
          . "Please go to Settings tab → 'Select Device GUI EXE'`n"
          . "to choose the executable path for this device.",
            "Device GUI Editor - Not Configured",
            "Icon! T1.5"
        )
        return
    }
    if !FileExist(currentDeviceGuiExe) {
        MsgBox(
            "The selected Device GUI EXE path does not exist:`n" . currentDeviceGuiExe . "`n`n"
          . "Please go to Settings → 'Select Device GUI EXE'`n"
          . "and choose a valid executable for device: " . selectedDevice,
            "Device GUI Editor - File Missing",
            "Iconx T1.5"
        )
        return
    }
    try Run(currentDeviceGuiExe)
    catch as err {
        MsgBox("Failed to launch Device GUI for " . selectedDevice . ":`n" . err.Message, "Launch Error", "Iconx T1.5")
    }
}

LaunchGameByName(gameName, deviceName := "") {
    global games, gamesFile, defaultProfileDelay, selectedDevice, deviceGuiExe, minimizeGuiAfterImport
    local deviceToUse, exe, prof, delay, launch, closeManager, guiCloseDelay, lastPlayed, count
    local currentDeviceGuiExe, processName
    
    deviceToUse := deviceName != "" ? deviceName : selectedDevice
    
    if (deviceToUse = "") {
        deviceToUse := "Default"
    }
    
    exe := games[gameName]["Exe"]
    
    prof := GetGameProfileForDevice(gameName, deviceToUse)
    
    delay := games[gameName]["PostImportDelay"]
    launch := games[gameName]["LaunchExe"]
    closeManager := games[gameName].Has("CloseManager") ? games[gameName]["CloseManager"] : 1
    
    guiCloseDelay := IniRead(gamesFile, "Games", gameName . ".GuiCloseDelay", defaultProfileDelay)
    
    lastPlayed := CurrentIsoTimestamp()
    
    count := games[gameName]["LaunchCount"]
    if (count = "")
        count := 0
    count++
    
    if (prof != "")
        ImportProfile(prof, guiCloseDelay)
    
    if (launch = 1 && exe != "") {
        if (delay != "" && delay is integer)
            Sleep(delay)
        
        SaveGameToIni(gameName, exe, prof, delay, launch, 
                      games[gameName]["Added"], lastPlayed, count, closeManager)
        
        currentDeviceGuiExe := deviceGuiExe.Has(deviceToUse) ? deviceGuiExe[deviceToUse] : ""
        if (currentDeviceGuiExe != "") {
            processName := SubStr(currentDeviceGuiExe, InStr(currentDeviceGuiExe, "\",, -1) + 1)
            
            ; Check if we should minimize instead of close
            if (minimizeGuiAfterImport = 1) {
                ; Minimize instead of close
                if WinExist("ahk_exe " . processName) {
                    WinMinimize("ahk_exe " . processName)
                }
            } else {
                ; Try softer closure method
                if WinExist("ahk_exe " . processName) {
                    WinClose("ahk_exe " . processName)
                    Sleep(500)  ; Give it time
                    
                    ; If still exists, try Alt+F4
                    if WinExist("ahk_exe " . processName) {
                        WinActivate("ahk_exe " . processName)
                        Sleep(100)
                        Send("!{F4}")
                    }
                }
            }
        }
        
        Run('cmd.exe /c timeout /t 1 /nobreak >nul & start "" "' . exe . '"', , "Hide")
        
        if (closeManager = 1) {
            Sleep(500)
            ExitApp
        }
    } else {
        SaveGameToIni(gameName, exe, prof, delay, launch, 
                      games[gameName]["Added"], lastPlayed, count, closeManager)
        
        if (closeManager = 1) {
            Sleep(500)
            ExitApp
        }
    }
}

StrTitle(str) {
    local words, result, index, word, firstChar, restOfWord
    
    if (str = "")
        return ""
    
    words := StrSplit(str, A_Space)
    result := ""
    
    for index, word in words {
        if (word = "")
            continue
            
        firstChar := SubStr(word, 1, 1)
        restOfWord := SubStr(word, 2)
        
        firstChar := StrUpper(firstChar)
        restOfWord := StrLower(restOfWord)
        
        result .= (result != "" ? A_Space : "") . firstChar . restOfWord
    }
    
    return result
}

SaveDelayBtn_Click(*) {
    global gamesFile, selectedDevice, clickDelayEdit, deviceClickDelay
    local newDelay, delayValue
    
    newDelay := Trim(clickDelayEdit.Value)
    
    if (newDelay = "" || !RegExMatch(newDelay, "^\d+$")) {
        MsgBox("Please enter a valid number for click delay.", "Invalid Input", "Icon! T1.5")
        return
    }
    
    delayValue := Integer(newDelay)
    if (delayValue < 0) {
        MsgBox("Click delay cannot be negative.", "Invalid Input", "Icon! T1.5")
        return
    }
    
    deviceClickDelay[selectedDevice] := delayValue
    IniWrite(delayValue, gamesFile, "Device_" . selectedDevice, "ClickDelay")
    MsgBox("Click delay saved for device " . selectedDevice . ": " . delayValue . "ms", "Success", "Iconi T1.5")
}

SaveMinimizeGuiSetting(*) {
    global gamesFile, minimizeGuiCheckbox, minimizeGuiAfterImport
    
    minimizeGuiAfterImport := minimizeGuiCheckbox.Value
    IniWrite(minimizeGuiAfterImport, gamesFile, "Config", "MinimizeGuiAfterImport")
    MsgBox("Setting saved: " . (minimizeGuiAfterImport ? "GUI will minimize after import" : "GUI will close after import"), "Success", "Iconi T1.5")
}

; ===== GUI Creation =====
mainGui := Gui("+Resize +MinSize525x750 -Theme +OwnDialogs", "Device GUI Manager")
mainGui.OnEvent("Close", ExitWithDeviceGuiClose)
mainGui.SetFont("s11")
mainGui.BackColor := bgColorCfg
tabs := mainGui.AddTab3("x10 y10 w515 h720", ["Game Launcher", "Profile Manager", "Game Editor", "Settings"])
tabs.Value := lastTab
ApplyTextColor(textColorCfg)

; TAB 1 - Game Launcher
tabs.UseTab(1)
mainGui.AddText("x20 y50 w60", "Device:")
launcherDeviceDrop := mainGui.AddDropDownList("x80 y48 w200 +Border")
mainGui.AddText("x290 y50 w60", "Search:")
launcherSearchEdit := mainGui.AddEdit("x350 y48 w150", "")
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
mainGui.AddText("x20 y50 w60", "Device:")
profilesDeviceDrop := mainGui.AddDropDownList("x80 y48 w200 +Border")
mainGui.AddText("x290 y50 w60", "Search:")
profilesSearchEdit := mainGui.AddEdit("x350 y48 w150", "")
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
mainGui.AddText("x20 y50 w60", "Device:")
editorDeviceDrop := mainGui.AddDropDownList("x80 y48 w200 +Border")
mainGui.AddText("x290 y50 w60", "Search:")
editorSearchEdit := mainGui.AddEdit("x350 y48 w150", "")
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
mainGui.AddText("x193 y700 w140 h20", "GUI Close Delay (ms):")
guiCloseDelayEdit := mainGui.AddEdit("x305 y698 w65 h22 +Border Number", defaultProfileDelay)

; TAB 4 - Settings
tabs.UseTab(4)

settingsColorsBox := mainGui.AddGroupBox("x20 y50 w460 h80", "Colors")
bgColorLabel := mainGui.AddText("x40 y75 w80 h20", "BG Color:")
bgColorBtn := mainGui.AddButton("x120 y73 w100 h24", "Pick")
textColorPreview := mainGui.AddText("x240 y73 w200 h24 Center", "Text Preview")

settingsSortBox := mainGui.AddGroupBox("x20 y140 w460 h80", "Sorting")
mainGui.AddText("x40 y165 w120 h20", "Sort Games By:")
gamesSortDrop := mainGui.AddDropDownList("x160 y163 w140 +Border", ["Alphabetical", "TimeAdded", "LastPlayed"])
mainGui.AddText("x310 y165 w80 h20", "Order:")
orderSortDrop := mainGui.AddDropDownList("x360 y163 w100 +Border", ["Ascending", "Descending"])

gamesSortDrop.Text := sortGamesMode
orderSortDrop.Text := sortOrder

settingsDeviceBox := mainGui.AddGroupBox("x20 y230 w460 h210", "Device GUI Automation")

launchEditorBtn := mainGui.AddButton("x40 y260 w180 h28", "Launch Device GUI Editor")
captureImportBtn := mainGui.AddButton("x240 y260 w180 h28", "Capture Import Button")

openProfilesBtn := mainGui.AddButton("x40 y295 w180 h28", "Open Program Folder")
testImportBtn := mainGui.AddButton("x240 y295 w180 h28", "Test Import Click")

selectDeviceGuiExeBtn := mainGui.AddButton("x40 y330 w180 h28", "Select Device GUI EXE")
openProfileFolderBtn := mainGui.AddButton("x240 y330 w180 h28", "Open Profile Folder")

mainGui.AddText("x40 y365 w120 h20", "Click Delay (ms):")
clickDelayEdit := mainGui.AddEdit("x160 y370 w80 h24 +Border Number", GetDeviceClickDelay(selectedDevice))
saveDelayBtn := mainGui.AddButton("x250 y370 w130 h24", "Save Click Delay")

; Add minimize GUI checkbox here
minimizeGuiCheckbox := mainGui.AddCheckBox("x40 y405 w180 h20", "Minimize GUI after import")
minimizeGuiCheckbox.Value := minimizeGuiAfterImport

selectDeviceProfileDirBtn := mainGui.AddButton("x40 y430 w380 h28", "Set Device Profile Folder")

settingsDevicesBox := mainGui.AddGroupBox("x20 y470 w460 h120", "Devices")

mainGui.AddText("x40 y500 w80 h20", "Device:")
devicesDrop := mainGui.AddDropDownList("x120 y498 w200 +Border")
addDeviceBtn := mainGui.AddButton("x330 y498 w70 h24", "Add")
deleteDeviceBtn := mainGui.AddButton("x405 y498 w70 h24", "Delete")

mainGui.AddText("x40 y530 w120 h20", "Profile Ext:")
profileExtDrop := mainGui.AddDropDownList("x120 y528 w140 +Border")
addExtEdit := mainGui.AddEdit("x270 y528 w70 h22 +Border")
addExtBtn := mainGui.AddButton("x345 y528 w80 h24", "Add Ext")

settingsExitBtn := mainGui.AddButton("x295 y600 w185 h30", "Exit Program")

textColorPreview.SetFont("s11 " . "c" . SubStr(textColorCfg, 3))
for c in mainGui
    try c.Opt("Background" . SubStr(bgColorCfg, 3))

PopulateAllDeviceDropdowns() {
    global devicesDrop, launcherDeviceDrop, profilesDeviceDrop, editorDeviceDrop, devices, selectedDevice
    local dropdown, tempDev, idx, i
    
    for dropdown in [devicesDrop, launcherDeviceDrop, profilesDeviceDrop, editorDeviceDrop] {
        dropdown.Delete()
        for tempDev in devices {
            dropdown.Add([tempDev])
        }
        
        if (selectedDevice != "") {
            idx := 0, i := 0
            for tempDev in devices {
                i++
                if (tempDev = selectedDevice) {
                    idx := i
                    break
                }
            }
            if (idx > 0)
                dropdown.Choose(idx)
        }
    }
}

HandleDeviceChange(newDevice, caller) {
    global selectedDevice, gamesFile, deviceCurrentExt, deviceExtensions, currentProfileExtension, editorDeviceLabel, clickDelayEdit, deviceClickDelay
    local currentDelay
    
    if (newDevice = "")
        return
    
    selectedDevice := newDevice
    IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")
    
    PopulateAllDeviceDropdowns()
    
    if !deviceExtensions.Has(selectedDevice)
        deviceExtensions[selectedDevice] := []
    if !deviceCurrentExt.Has(selectedDevice) {
        if (deviceExtensions[selectedDevice].Length > 0)
            deviceCurrentExt[selectedDevice] := deviceExtensions[selectedDevice][1]
        else
            deviceCurrentExt[selectedDevice] := "*"
        IniWrite(deviceCurrentExt[selectedDevice], gamesFile, "DeviceCurrentExt", selectedDevice)
    }
    currentProfileExtension := deviceCurrentExt[selectedDevice]
    
    currentDelay := GetDeviceClickDelay(selectedDevice)
    clickDelayEdit.Value := currentDelay
    
    PopulateProfileExtDrop()
    
    PopulateGameListControls()
    PopulateProfileList()
}

bgColorBtn.OnEvent("Click", PickBackgroundColor)
gamesSortDrop.OnEvent("Change", SortSettingsChanged)
orderSortDrop.OnEvent("Change", SortSettingsChanged)

launchEditorBtn.OnEvent("Click", LaunchDeviceGuiEditor)
captureImportBtn.OnEvent("Click", (*) => CaptureImportButtonCoords())
openProfilesBtn.OnEvent("Click", (*) => Run(A_ScriptDir))
testImportBtn.OnEvent("Click", TestImportClick)
selectDeviceGuiExeBtn.OnEvent("Click", SelectDeviceGuiExe)
openProfileFolderBtn.OnEvent("Click", OpenCurrentDeviceProfileFolder)
selectDeviceProfileDirBtn.OnEvent("Click", (*) => SelectDeviceProfileDir())
saveDelayBtn.OnEvent("Click", SaveDelayBtn_Click)
minimizeGuiCheckbox.OnEvent("Click", SaveMinimizeGuiSetting)  ; Added this line

devicesDrop.OnEvent("Change", (*) => HandleDeviceChange(devicesDrop.Text, "settings"))
launcherDeviceDrop.OnEvent("Change", (*) => HandleDeviceChange(launcherDeviceDrop.Text, "launcher"))
profilesDeviceDrop.OnEvent("Change", (*) => HandleDeviceChange(profilesDeviceDrop.Text, "profiles"))
editorDeviceDrop.OnEvent("Change", (*) => HandleDeviceChange(editorDeviceDrop.Text, "editor"))
profileExtDrop.OnEvent("Change", ProfileExtChanged)
addDeviceBtn.OnEvent("Click", AddNewDevice)
deleteDeviceBtn.OnEvent("Click", DeleteSelectedDevice)
addExtBtn.OnEvent("Click", AddExtensionToDevice)

settingsExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)

lbLauncher.OnEvent("Change", LauncherGameSelected)
lbLauncher.OnEvent("DoubleClick", LaunchSelectedGame)
launchBtn.OnEvent("Click", LaunchSelectedGame)
launcherOpenFolderBtn.OnEvent("Click", OpenCurrentDeviceProfileFolder)
launcherLaunchEditorBtn.OnEvent("Click", LaunchDeviceGuiEditor)
launcherExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)

lbProfiles.OnEvent("Change", ProfileSelected)
lbProfiles.OnEvent("DoubleClick", ImportSelectedProfile)
profilesImportBtn.OnEvent("Click", ImportSelectedProfile)
profilesOpenFolderBtn.OnEvent("Click", OpenCurrentDeviceProfileFolder)
profilesBackupBtn.OnEvent("Click", BackupSelectedProfile)
profilesSetFolderBtn.OnEvent("Click", SelectProfilesFolder)
profilesLaunchEditorBtn.OnEvent("Click", LaunchDeviceGuiEditor)
profilesExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)

lbGames.OnEvent("Change", PopulateGameFields)
editorAddBtn.OnEvent("Click", AddOrUpdateGame)
editorRemoveBtn.OnEvent("Click", RemoveSelectedGame)
editorCreateShortcutBtn.OnEvent("Click", CreateGameShortcut)
editorClearBtn.OnEvent("Click", ClearEditorFields)
editorOpenFolderBtn.OnEvent("Click", OpenCurrentDeviceProfileFolder)
editorExitBtn.OnEvent("Click", ExitWithDeviceGuiClose)
editorBrowseExeBtn.OnEvent("Click", BrowseGameExe)
editorOpenExeFolderBtn.OnEvent("Click", OpenExeFolder)
editorBrowseProfileBtn.OnEvent("Click", BrowseProfileFile)

launcherSearchEdit.OnEvent("Change", FilterLauncherList)
profilesSearchEdit.OnEvent("Change", FilterProfilesList)
editorSearchEdit.OnEvent("Change", FilterGamesList)
launcherNotesEdit.OnEvent("Focus", LauncherNotesEditFocused)
launcherNotesEdit.OnEvent("LoseFocus", SaveLauncherNotes)
profilesNotesEdit.OnEvent("Focus", ProfilesNotesEditFocused)
profilesNotesEdit.OnEvent("LoseFocus", SaveProfileNotes)
tabs.OnEvent("Change", TabChanged)

TabChanged(*) {
    if (tabs.Value = 1) {
        LoadGames()
        PopulateGameListControls()
    }
    else if (tabs.Value = 2) {
        PopulateProfileList()
    }
    else if (tabs.Value = 3) {
        PopulateGameListControls()
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
    global gameNameEdit, gameExeEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, games, closeManagerCheckbox, guiCloseDelayEdit, gamesFile, defaultProfileDelay, selectedDevice
    local localGameName, exe, prof, delay, launch, closeManager, added, guiCloseDelay
    
    localGameName := Trim(gameNameEdit.Value)
    exe := Trim(gameExeEdit.Value)
    prof := Trim(gameProfileEdit.Value)
    delay := Trim(gameDelayEdit.Value)
    launch := launchExeCheckbox.Value
    closeManager := closeManagerCheckbox.Value
    
    if (localGameName = "") {
        MsgBox("Game name cannot be empty.", "Error", "Icon! T1.5")
        return
    }
    
    added := (!games.Has(localGameName)) ? CurrentIsoTimestamp() : games[localGameName]["Added"]
    SaveGameToIni(localGameName, exe, prof, delay, launch, added, "", "", closeManager)
    
    guiCloseDelay := Trim(guiCloseDelayEdit.Value)
    if (guiCloseDelay = "" || !RegExMatch(guiCloseDelay, "^\d+$")) {
        guiCloseDelay := defaultProfileDelay
    }
    IniWrite(guiCloseDelay, gamesFile, "Games", localGameName . ".GuiCloseDelay")
    
    LoadGames()
    PopulateGameListControls()
    PopulateProfileList()
    MsgBox("Game saved for device: " . selectedDevice, "Success", "Iconi T1.5")
}

RemoveSelectedGame(*) {
    global lbGames, games, gamesFile, selectedDevice
    local localGameName, baseGameName, deviceProfileKey, oldProfileKey, hasOtherProfiles, gameLine, gameParts, key
    
    localGameName := lbGames.Text
    if (localGameName = "") {
        MsgBox("No game selected.", "Error", "Icon! T1.5")
        return
    }
    
    baseGameName := GetBaseGameName(localGameName)
    
    deviceProfileKey := baseGameName . ".Profile" . selectedDevice
    IniDelete(gamesFile, "Games", deviceProfileKey)
    
    oldProfileKey := baseGameName . selectedDevice . ".Profiles"
    IniDelete(gamesFile, "Games", oldProfileKey)
    
    hasOtherProfiles := false
    try gameEntries := IniRead(gamesFile, "Games")
    catch
        gameEntries := ""
    
    if (gameEntries != "") {
        for gameLine in StrSplit(gameEntries, "`n", "`r") {
            gameLine := Trim(gameLine)
            if (gameLine = "" || !InStr(gameLine, "="))
                continue
            gameParts := StrSplit(gameLine, "=")
            key := Trim(gameParts[1])
            if (InStr(key, baseGameName . ".Profile") && key != deviceProfileKey) {
                hasOtherProfiles := true
                break
            }
            if (InStr(key, baseGameName . "M913-")) {
                hasOtherProfiles := true
                break
            }
        }
    }
    
    if (!hasOtherProfiles) {
        if (MsgBox("This game has no profiles for other devices. Remove entire game entry?", "Confirm Removal", "YesNo Icon!") = "Yes") {
            RemoveGameFromIni(baseGameName)
            IniDelete(gamesFile, "Games", baseGameName . ".GuiCloseDelay")
        }
    }
    
    LoadGames()
    PopulateGameListControls()
    MsgBox("Profile removed for device: " . selectedDevice, "Success", "Iconi T1.5")
}

BackupSelectedProfile(*) {
    global lbProfiles, backupDir, selectedDevice
    local localProfileName, currentProfileDir, src, dest
    
    localProfileName := lbProfiles.Text
    if (localProfileName = "") {
        MsgBox("No profile selected.", "Error", "Icon! T1.5")
        return
    }
    currentProfileDir := GetDeviceProfileDir(selectedDevice)
    src := currentProfileDir . "\" . localProfileName
    dest := backupDir . "\" . localProfileName
    if !DirExist(backupDir)
        DirCreate(backupDir)
    FileCopy(src, dest, 1)
    MsgBox("Profile backed up.", "Success", "Iconi T1.5")
}

BrowseGameExe(*) {
    global gameExeEdit, gameNameEdit, lastExeDir, gamesFile
    local chosen, dir, outNameNoExt
    
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
    global gameProfileEdit, currentProfileExtension, selectedDevice
    local currentProfileDir, filter, chosen
    
    currentProfileDir := GetDeviceProfileDir(selectedDevice)
    filter := (currentProfileExtension = "*" || currentProfileExtension = "")
        ? "All Files (*.*)"
        : "Profiles (*." . currentProfileExtension . ")"
    chosen := FileSelect(3, currentProfileDir, "Select Profile File", filter)
    if (chosen != "")
        gameProfileEdit.Value := chosen
}

OpenExeFolder(*) {
    global gameExeEdit
    local exe, outFile, dir
    
    exe := gameExeEdit.Value
    if (exe = "")
        return
    SplitPath(exe, &outFile, &dir)
    Run(dir)
}

CreateGameShortcut(*) {
    global lbGames, games, selectedDevice
    local localGameName, baseGameName, exe, shortcutName, shortcutPath, ahkPath, shortcut
    
    localGameName := lbGames.Text
    if (localGameName = "") {
        MsgBox("No game selected.", "Error", "Icon! T1.5")
        return
    }
    
    baseGameName := GetBaseGameName(localGameName)
    
    exe := games[baseGameName]["Exe"]
    if (exe = "") {
        MsgBox("No EXE set for this game.", "Error", "Icon! T1.5")
        return
    }
    
    shortcutName := baseGameName . " (" . selectedDevice . ")"
    shortcutPath := FileSelect("S", A_Desktop . "\" . shortcutName . ".lnk", "Save Shortcut As", "Shortcuts (*.lnk)")
    if (shortcutPath = "")
        return
    
    ahkPath := A_ScriptFullPath
    shortcut := ComObject("WScript.Shell").CreateShortcut(shortcutPath)
    shortcut.TargetPath := ahkPath
    shortcut.Arguments := '/launch "' . baseGameName . '" "' . selectedDevice . '"'
    shortcut.WorkingDirectory := A_ScriptDir
    shortcut.IconLocation := exe . ",0"
    shortcut.Save()
    
    MsgBox("Shortcut created at: " . shortcutPath . 
           "`n`nGame: " . baseGameName . 
           "`nDevice: " . selectedDevice . 
           "`nArguments: " . '/launch "' . baseGameName . '" "' . selectedDevice . '"', 
           "Success", "Iconi T5")
}

LaunchSelectedGame(*) {
    global lbLauncher, games, selectedDevice
    local localGameName, baseGameName
    
    localGameName := lbLauncher.Text
    if (localGameName = "") {
        MsgBox("No game selected.", "Error", "Icon! T1.5")
        return
    }
    
    baseGameName := GetBaseGameName(localGameName)
    
    LaunchGameByName(baseGameName)
}

ImportSelectedProfile(*) {
    global lbProfiles, games, gamesFile, defaultProfileDelay, selectedDevice
    local localProfileName, guiCloseDelay, currentProfileDir, profilePath, gameName, gameData, key, value
    
    localProfileName := lbProfiles.Text
    if (localProfileName != "") {
        LoadGames()
        guiCloseDelay := defaultProfileDelay
        currentProfileDir := GetDeviceProfileDir(selectedDevice)
        profilePath := currentProfileDir . "\" . localProfileName
        
        for gameName, gameData in games {
            for key, value in gameData {
                if (InStr(key, "Profile_") && value = profilePath) {
                    guiCloseDelay := IniRead(gamesFile, "Games", gameName . ".GuiCloseDelay", defaultProfileDelay)
                    break 2
                }
            }
        }
        
        ImportProfile(profilePath, guiCloseDelay)
    }
    else
        MsgBox("No profile selected.", "Error", "Icon! T1.5")
}

PickBackgroundColor(*) {
    global mainGui, gamesFile, bgColorCfg, textColorCfg, textColorPreview
    local pickedColor, cr
    
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
    
    PopulateGameListControls()
    PopulateProfileList()
}

ProfileExtChanged(*) {
    global profileExtDrop, selectedDevice, deviceExtensions, deviceCurrentExt, currentProfileExtension
    local label, ext
    
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
    global gamesFile, selectedDevice, deviceGuiExe
    local chosen
    
    chosen := FileSelect(3, , "Select Device GUI EXE for " . selectedDevice, "Executables (*.exe)")
    if (chosen != "") {
        deviceGuiExe[selectedDevice] := chosen
        IniWrite(chosen, gamesFile, "Device_" . selectedDevice, "DeviceGuiExe")
        MsgBox("Device GUI EXE updated for " . selectedDevice . " to:`n" . chosen, "Success", "Iconi T1.5")
    }
}

OpenCurrentDeviceProfileFolder(*) {
    global selectedDevice
    local currentProfileDir
    
    currentProfileDir := GetDeviceProfileDir(selectedDevice)
    if DirExist(currentProfileDir) {
        Run(currentProfileDir)
    } else {
        MsgBox("Profile folder does not exist for device: " . selectedDevice . "`n`n" . currentProfileDir, "Folder Not Found", "Icon! T1.5")
    }
}

SelectDeviceProfileDir() {
    global gamesFile, selectedDevice, deviceProfileDir
    local currentDir, selectedFolder
    
    if (selectedDevice = "") {
        MsgBox("No device selected.", "Set Profile Folder", "Icon! T1.5")
        return
    }
    
    currentDir := GetDeviceProfileDir(selectedDevice)
    
    selectedFolder := DirSelect("*" . currentDir, 3, "Choose profile folder for device: " . selectedDevice)
    if (selectedFolder = "")
        return
    
    deviceProfileDir[selectedDevice] := selectedFolder
    IniWrite(selectedFolder, gamesFile, "Device_" . selectedDevice, "ProfileDir")
    MsgBox("Profile folder set for device " . selectedDevice . " to:`n" . selectedFolder, "Success", "Iconi T1.5")
    
    if (tabs.Value = 2) {
        PopulateProfileList()
    }
}

SelectProfilesFolder(*) {
    global profileDir, gamesFile
    local selectedFolder
    
    selectedFolder := DirSelect("*" . profileDir, 3, "Choose the folder where your profile files are stored")
    if (selectedFolder = "")
        return
    profileDir := selectedFolder
    IniWrite(profileDir, gamesFile, "Config", "ProfilesDir")
    MsgBox("Profiles folder set to:`n" . profileDir, "Profiles Folder Updated", "Iconi T1.5")
    PopulateProfileList()
}

ExitWithDeviceGuiClose(*) {
    global mainGui, gamesFile, tabs, selectedDevice, deviceGuiExe
    local x, y, processName
    
    WinGetPos(&x, &y, , , mainGui.Hwnd)
    IniWrite(x, gamesFile, "Config", "WinX")
    IniWrite(y, gamesFile, "Config", "WinY")
    IniWrite(tabs.Value, gamesFile, "Config", "LastTab")
    
    if (deviceGuiExe.Has(selectedDevice) && deviceGuiExe[selectedDevice] != "") {
        processName := SubStr(deviceGuiExe[selectedDevice], InStr(deviceGuiExe[selectedDevice], "\",, -1) + 1)
        if WinExist("ahk_exe " . processName)
            WinClose("ahk_exe " . processName)
    }
    
    ExitApp
}

PopulateGameFields(*) {
    global lbGames, selGameLabel, gameNameEdit, gameExeEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, closeManagerCheckbox, guiCloseDelayEdit, games, gamesFile, defaultProfileDelay, selectedDevice
    local localGameName, baseGameName, data, deviceProfileKey, guiCloseDelay
    
    localGameName := lbGames.Text
    selGameLabel.Text := (localGameName = "") ? "" : "Selected: " . localGameName
    if (localGameName = "") {
        gameNameEdit.Value := ""
        gameExeEdit.Value := ""
        gameProfileEdit.Value := ""
        gameDelayEdit.Value := ""
        launchExeCheckbox.Value := 1
        closeManagerCheckbox.Value := 1
        guiCloseDelayEdit.Value := defaultProfileDelay
        return
    }
    
    baseGameName := GetBaseGameName(localGameName)
    
    data := games[baseGameName]
    gameNameEdit.Value := baseGameName
    gameExeEdit.Value := data["Exe"]
    
    deviceProfileKey := "Profile_" . selectedDevice
    if (data.Has(deviceProfileKey)) {
        gameProfileEdit.Value := data[deviceProfileKey]
    } else {
        gameProfileEdit.Value := ""
    }
    
    gameDelayEdit.Value := data["PostImportDelay"]
    launchExeCheckbox.Value := data["LaunchExe"]
    closeManagerCheckbox.Value := data.Has("CloseManager") ? data["CloseManager"] : 1
    
    guiCloseDelay := IniRead(gamesFile, "Games", baseGameName . ".GuiCloseDelay", defaultProfileDelay)
    guiCloseDelayEdit.Value := guiCloseDelay
}

LauncherGameSelected(*) {
    global lbLauncher, launcherSelLabel, launcherNotesEdit, games, profiles, selectedDevice
    local localGameName, baseGameName, deviceProfileKey, profilePath, profileName
    
    localGameName := lbLauncher.Text
    launcherSelLabel.Text := (localGameName = "") ? "" : "Selected: " . localGameName
    
    baseGameName := GetBaseGameName(localGameName)
    
    deviceProfileKey := "Profile_" . selectedDevice
    profilePath := ""
    
    if (baseGameName != "" && games.Has(baseGameName)) {
        if (games[baseGameName].Has(deviceProfileKey)) {
            profilePath := games[baseGameName][deviceProfileKey]
        }
    }
    
    if (profilePath != "") {
        profileName := RegExReplace(profilePath, ".*\\", "")
        launcherNotesEdit.Value := profiles.Has(profileName) ? profiles[profileName]["Notes"] : ""
    } else {
        launcherNotesEdit.Value := ""
    }
}

ProfileSelected(*) {
    global lbProfiles, profileSelLabel, profilesNotesEdit, profiles
    local localProfileName
    
    localProfileName := lbProfiles.Text
    profileSelLabel.Text := (localProfileName = "") ? "" : "Selected: " . localProfileName
    profilesNotesEdit.Value := (localProfileName = "") ? "" : (profiles.Has(localProfileName) ? profiles[localProfileName]["Notes"] : "")
}

SaveLauncherNotes(*) {
    global launcherNotesEdit, current_notes_game, games, profiles, gamesFile, selectedDevice
    local baseGameName, deviceProfileKey, profilePath, profileName, notes
    
    if (current_notes_game = "")
        return
    
    baseGameName := GetBaseGameName(current_notes_game)
    
    deviceProfileKey := "Profile_" . selectedDevice
    profilePath := ""
    
    if (games[baseGameName].Has(deviceProfileKey)) {
        profilePath := games[baseGameName][deviceProfileKey]
    }
    
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
    local notes
    
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
    global lbLauncher, lbGames, games, sortGamesMode, sortOrder, fullGameNames, selectedDevice
    local selectedLauncher, selectedEditor, filteredGames, gameName, displayName, idx, index, gameItem
    
    LoadGames()
    
    selectedLauncher := lbLauncher.Text
    selectedEditor := lbGames.Text
    
    lbLauncher.Delete()
    lbGames.Delete()
    
    filteredGames := GetGamesForCurrentDevice()
    
    fullGameNames := SortGameNames(filteredGames, sortGamesMode, sortOrder)
    
    for gameName in fullGameNames {
        displayName := gameName . " (" . selectedDevice . ")"
        lbLauncher.Add([displayName])
        lbGames.Add([displayName])
    }
    
    if (selectedLauncher != "") {
        idx := 0
        for index, gameItem in fullGameNames {
            displayName := gameItem . " (" . selectedDevice . ")"
            if (displayName = selectedLauncher) {
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
            displayName := gameItem . " (" . selectedDevice . ")"
            if (displayName = selectedEditor) {
                idx := index
                break
            }
        }
        if (idx > 0)
            lbGames.Choose(idx)
    }
}

PopulateProfileList() {
    global lbProfiles, sortProfilesMode, sortOrder, fullProfileNames, selectedDevice
    local currentProfileDir, v
    
    lbProfiles.Delete()
    
    currentProfileDir := GetDeviceProfileDir(selectedDevice)
    fullProfileNames := SortProfileNames(currentProfileDir, sortProfilesMode, sortOrder)
    for v in fullProfileNames
        lbProfiles.Add([v])
}

FilterLauncherList(*) {
    global lbLauncher, fullGameNames, launcherSearchEdit, selectedDevice
    local searchText, searchLower, gameName, displayName
    
    searchText := launcherSearchEdit.Value
    lbLauncher.Delete()
    
    if (searchText = "") {
        for gameName in fullGameNames {
            displayName := gameName . " (" . selectedDevice . ")"
            lbLauncher.Add([displayName])
        }
    } else {
        searchLower := StrLower(searchText)
        for gameName in fullGameNames {
            displayName := gameName . " (" . selectedDevice . ")"
            if (InStr(StrLower(displayName), searchLower)) {
                lbLauncher.Add([displayName])
            }
        }
    }
}

FilterGamesList(*) {
    global lbGames, fullGameNames, editorSearchEdit, selectedDevice
    local searchText, searchLower, gameName, displayName
    
    searchText := editorSearchEdit.Value
    lbGames.Delete()
    
    if (searchText = "") {
        for gameName in fullGameNames {
            displayName := gameName . " (" . selectedDevice . ")"
            lbGames.Add([displayName])
        }
    } else {
        searchLower := StrLower(searchText)
        for gameName in fullGameNames {
            displayName := gameName . " (" . selectedDevice . ")"
            if (InStr(StrLower(displayName), searchLower)) {
                lbGames.Add([displayName])
            }
        }
    }
}

FilterProfilesList(*) {
    global lbProfiles, fullProfileNames, profilesSearchEdit
    local searchText, searchLower, item
    
    lbProfiles.Delete()
    searchText := profilesSearchEdit.Value
    
    if (searchText = "") {
        for item in fullProfileNames {
            lbProfiles.Add([item])
        }
    } else {
        searchLower := StrLower(searchText)
        for item in fullProfileNames {
            if (InStr(StrLower(item), searchLower)) {
                lbProfiles.Add([item])
            }
        }
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
    guiCloseDelayEdit.Value := defaultProfileDelay
    lbGames.Choose(0)
    selGameLabel.Text := ""
}

PopulateDevicesUi() {
    global profileExtDrop, selectedDevice, deviceExtensions, deviceCurrentExt, currentProfileExtension, clickDelayEdit, deviceClickDelay, clickDelayGlobal
    local currentDelay
    
    PopulateAllDeviceDropdowns()
    
    currentDelay := GetDeviceClickDelay(selectedDevice)
    clickDelayEdit.Value := currentDelay
    
    PopulateProfileExtDrop()
    
    PopulateGameListControls()
}

PopulateProfileExtDrop() {
    global profileExtDrop, selectedDevice, deviceExtensions, deviceCurrentExt, currentProfileExtension
    local extArr, curExt, idx, i, ext, label
    
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

AddNewDevice(*) {
    global gamesFile, devices, selectedDevice, deviceExtensions, deviceCurrentExt, deviceGuiExe, deviceClickDelay, clickDelayGlobal, deviceProfileDir, profileDir
    local newDevName, idx
    
    newDevName := InputBox("Enter new device name:", "Add New Device").Value
    newDevName := Trim(newDevName)
    if (newDevName = "")
        return
    if DeviceExists(newDevName) {
        MsgBox("A device with that name already exists.", "Duplicate Device", "Icon! T1.5")
        return
    }
    idx := devices.Length + 1
    IniWrite(newDevName, gamesFile, "Devices", "Device" . idx)
    devices.Push(newDevName)
    deviceExtensions[newDevName] := []
    deviceCurrentExt[newDevName] := "*"
    deviceGuiExe[newDevName] := ""
    deviceClickDelay[newDevName] := clickDelayGlobal
    deviceProfileDir[newDevName] := profileDir
    IniWrite("*", gamesFile, "DeviceCurrentExt", newDevName)
    selectedDevice := newDevName
    IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")
    PopulateDevicesUi()
    PopulateProfileList()
}

DeleteSelectedDevice(*) {
    global gamesFile, devices, selectedDevice, deviceExtensions, deviceCurrentExt, deviceGuiExe, deviceClickDelay, deviceProfileDir
    local newDevices, tempDev, idx
    
    if (selectedDevice = "") {
        MsgBox("No device selected.", "Delete Device", "Icon! T1.5")
        return
    }
    if (devices.Length = 1) {
        MsgBox("You must have at least one device.", "Delete Device", "Icon! T1.5")
        return
    }
    if (MsgBox("Delete device '" . selectedDevice . "' and all its settings?", "Confirm Delete", "YesNo Icon!") != "Yes")
        return

    newDevices := []
    for tempDev in devices {
        if (tempDev != selectedDevice)
            newDevices.Push(tempDev)
    }
    devices := newDevices

    IniDelete(gamesFile, "Devices")
    idx := 1
    for tempDev in devices {
        IniWrite(tempDev, gamesFile, "Devices", "Device" . idx)
        idx++
    }

    if (deviceExtensions.Has(selectedDevice))
        deviceExtensions.Delete(selectedDevice)
    if (deviceCurrentExt.Has(selectedDevice))
        deviceCurrentExt.Delete(selectedDevice)
    if (deviceGuiExe.Has(selectedDevice))
        deviceGuiExe.Delete(selectedDevice)
    if (deviceClickDelay.Has(selectedDevice))
        deviceClickDelay.Delete(selectedDevice)
    if (deviceProfileDir.Has(selectedDevice))
        deviceProfileDir.Delete(selectedDevice)
    
    IniDelete(gamesFile, "DeviceExtensions", selectedDevice)
    IniDelete(gamesFile, "DeviceCurrentExt", selectedDevice)
    IniDelete(gamesFile, "Device_" . selectedDevice)

    selectedDevice := (devices.Length > 0) ? devices[1] : ""
    IniWrite(selectedDevice, gamesFile, "Config", "SelectedDevice")

    PopulateDevicesUi()
    PopulateProfileList()
}

AddExtensionToDevice(*) {
    global gamesFile, selectedDevice, deviceExtensions, deviceCurrentExt, addExtEdit
    local ext, arr, e
    
    if (selectedDevice = "") {
        MsgBox("No device selected.", "Add Extension", "Icon! T1.5")
        return
    }
    ext := Trim(addExtEdit.Value)
    if (SubStr(ext, 1, 1) = ".")
        ext := SubStr(ext, 2)
    if (StrLen(ext) != 3 || !RegExMatch(ext, "^[A-Za-z0-9]{3}$")) {
        MsgBox("Please enter a 3-character extension (letters/numbers).", "Invalid Extension", "Icon! T1.5")
        return
    }
    ext := StrLower(ext)
    arr := deviceExtensions.Has(selectedDevice) ? deviceExtensions[selectedDevice] : []
    for e in arr {
        if (StrLower(e) = ext) {
            MsgBox("That extension already exists for this device.", "Duplicate Extension", "Icon! T1.5")
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