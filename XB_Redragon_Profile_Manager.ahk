#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All
SetWorkingDir A_ScriptDir
gamesFile := A_ScriptDir . "\games.ini"
profileDir := IniRead(gamesFile, "Config", "ProfilesDir", A_ScriptDir . "\Profiles")
backupDir := A_ScriptDir . "\Backups"
redragonExe := IniRead(gamesFile, "Config", "RedragonExe", "C:\Program Files (x86)\Redragon M913\OemDrv.exe")
globalDefaultDelay := 0
bgColorCfg := IniRead(gamesFile, "Theme", "BgColor", "0xFFF3D4")
textColorCfg := IniRead(gamesFile, "Theme", "TextColor", "0x000000")
sortGamesMode := IniRead(gamesFile, "Sort", "Games", "Alphabetical")
sortProfilesMode := "Alphabetical"
sortOrder := IniRead(gamesFile, "Sort", "Order", "Ascending")
profileExtension := IniRead(gamesFile, "Config", "ProfileExtension", "jmk")
defaultProfile := IniRead(gamesFile, "Config", "DefaultProfile", "")
lastTab := IniRead(gamesFile, "Config", "LastTab", 1)
lastExeDir := IniRead(gamesFile, "Config", "LastExeDir", "")
trayMinimize := IniRead(gamesFile, "Config", "TrayMinimize", 1)
if (lastTab < 1 || lastTab > 4)
    lastTab := 1
games := Map()
profiles := Map()
fullGameNames := []
fullProfileNames := []
current_notes_game := ""
current_notes_profile := ""

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
    ; Safety check: if start is empty or invalid, default to white
    if (start = "" || !RegExMatch(start, "^0x[0-9A-Fa-f]{6}$"))
        start := "0xFFFFFF"
    
    start := Integer(start)  ; Now safe to convert
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
    ; Ensure returned color is always in correct 0xRRGGBB format
    if (SubStr(picked, 1, 1) = "#")
        picked := "0x" . SubStr(picked, 2)
    if (!RegExMatch(picked, "^0x[0-9A-Fa-f]{6}$"))
        picked := "0xFFEAD9"  ; fallback to default
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
        gameKey := kp[1], field := kp[2]
        if !games.Has(gameKey)
            games[gameKey] := Map("Exe","", "Profiles","", "PostImportDelay",1500, "LaunchExe",1, "Added","", "LastPlayed","", "LaunchCount",0)
        games[gameKey][field] := val
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

SaveGameToIni(gameName, exe, profs, delay, launch, added := "", last := "", count := "") {
    global gamesFile
    IniWrite(exe, gamesFile, "Games", gameName . ".Exe")
    IniWrite(profs, gamesFile, "Games", gameName . ".Profiles")
    IniWrite(delay, gamesFile, "Games", gameName . ".PostImportDelay")
    IniWrite(launch, gamesFile, "Games", gameName . ".LaunchExe")
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
    for n, _ in games
        names.Push(n)
    if (names.Length < 2)
        return names
    if (mode = "Alphabetical") {
        s := ""
        for v in names
            s .= v . "`n"
        s := RTrim(s, "`n")
        Sort s
        names := StrSplit(s, "`n")
    } else {
        temp := []
        for n in names {
            t := (mode = "TimeAdded") ? games[n]["Added"] : games[n]["LastPlayed"]
            if (t = "")
                t := "9999-99-99T99:99:99"
            temp.Push(t . "|" . n)
        }
        s := ""
        for v in temp
            s .= v . "`n"
        s := RTrim(s, "`n")
        Sort s
        names := []
        for line in StrSplit(s, "`n") {
            p := StrSplit(line, "|")
            names.Push(p[2])
        }
    }
    if (order = "Descending")
        names := ArrayReverse(names)
    return names
}

SortProfileNames(dir, mode, order) {
    items := []
    if !DirExist(dir)
        return items
    pattern := (profileExtension = "*") ? "*.*" : "*." . profileExtension
    loop Files, dir . "\" . pattern
        items.Push(A_LoopFileName)
    if (mode = "Alphabetical" && items.Length > 1) {
        s := ""
        for v in items
            s .= v . "`n"
        s := RTrim(s, "`n")
        Sort s
        items := StrSplit(s, "`n")
    }
    if (order = "Descending")
        items := ArrayReverse(items)
    return items
}

CaptureImportButtonCoords() {
    global gamesFile
    if !WinExist("ahk_exe OemDrv.exe") {
        MsgBox("Redragon is not running.")
        return
    }
    WinActivate("ahk_exe OemDrv.exe")
    Sleep(300)
    CoordMode("Mouse", "Screen")
    overlay := Gui("-Caption +AlwaysOnTop +ToolWindow -Theme")
    overlay.SetFont("s11")
    overlay.BackColor := "0xEEAA99"
    overlay.Opt("+LastFound")
    WinSetTransparent(200)
    overlay.Show("Center w340 h60")
    overlay.AddText("x10 y10 w320 h40", "Hover over IMPORT button`nPress F8 to capture coords")
    Hotkey("F8", CaptureImportButton_Fire, "On")
}

CaptureImportButton_Fire(*) {
    global gamesFile
    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)
    IniWrite(x, gamesFile, "Config", "ImportButtonX")
    IniWrite(y, gamesFile, "Config", "ImportButtonY")
    Hotkey("F8", "Off")
    MsgBox("Saved Import Button Coords:`nX=" . x . "`nY=" . y)
    try WinClose("ahk_class AutoHotkeyGUI")
}

TestImportClick(*) {
    global gamesFile
    x := IniRead(gamesFile, "Config", "ImportButtonX", "")
    y := IniRead(gamesFile, "Config", "ImportButtonY", "")
    if (x = "" || y = "") {
        MsgBox("No Import button coords saved yet.")
        return
    }
    if WinExist("Redragon") {
        WinActivate("Redragon")
        Sleep(300)
    }
    CoordMode("Mouse", "Screen")
    MouseMove(x, y, 10)
    Sleep(300)
    Click
}

ImportProfile(path) {
    global redragonExe, gamesFile
    if !FileExist(redragonExe) {
        MsgBox("Redragon software not found.")
        return
    }
    if !FileExist(path) {
        MsgBox("Profile file not found.")
        return
    }
    btnX := IniRead(gamesFile, "Config", "ImportButtonX", "")
    btnY := IniRead(gamesFile, "Config", "ImportButtonY", "")
    if (btnX = "" || btnY = "") {
        MsgBox("Import button coords not set.")
        return
    }
    if !ProcessExist("OemDrv.exe") {
        Run(redragonExe)
        Sleep(2000)
    }
    WinWait("ahk_exe OemDrv.exe", "", 10)
    if !WinExist("ahk_exe OemDrv.exe") {
        MsgBox("Could not find Redragon window.")
        return
    }
    WinActivate("ahk_exe OemDrv.exe")
    Sleep(300)
    CoordMode("Mouse", "Screen")
    MouseMove(btnX, btnY, 10)
    Sleep(100)
    Click
    Sleep(500)
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
    Sleep(1500)
    if ProcessExist("OemDrv.exe")
        ProcessClose("OemDrv.exe")
}

if (A_Args.Length > 0 && A_Args[1] = "/launch") {
    if (A_Args.Length < 2) {
        ExitApp
    }
    cliGameName := A_Args[2]
    LoadGames()
    if !games.Has(cliGameName) {
        ExitApp
    }
    LaunchGameByName(cliGameName)
    ExitApp
}

LaunchGameByName(cliGameName) {
    global games
    exe := games[cliGameName]["Exe"]
    prof := games[cliGameName]["Profiles"]
    delay := games[cliGameName]["PostImportDelay"]
    launch := games[cliGameName]["LaunchExe"]
    if (prof != "")
        ImportProfile(prof)
    if (launch = 1 && exe != "") {
        if (delay != "" && delay is integer)
            Sleep(delay)
        SaveGameToIni(cliGameName, exe, prof, delay, launch, games[cliGameName]["Added"], CurrentIsoTimestamp())
        if WinExist("ahk_exe OemDrv.exe")
            WinClose("ahk_exe OemDrv.exe")
        Run('cmd.exe /c timeout /t 1 /nobreak >nul & start "" "' . exe . '"', , "Hide")
    } else {
        SaveGameToIni(cliGameName, exe, prof, delay, launch, games[cliGameName]["Added"], CurrentIsoTimestamp())
    }
}

mainGui := Gui("+Resize +MinSize525x750 -Theme +OwnDialogs", "Redragon Manager")
mainGui.OnEvent("Close", ExitWithRedragonClose)
mainGui.SetFont("s11")
mainGui.BackColor := bgColorCfg
tabs := mainGui.AddTab3("x10 y10 w515 h720", ["Game Launcher", "Profile Manager", "Game Editor", "Settings"])
tabs.Value := lastTab
ApplyTextColor(textColorCfg)

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
launcherLaunchEditorBtn := mainGui.AddButton("x20 y640 w225 h30", "Launch Redragon Editor")
launcherExitBtn := mainGui.AddButton("x250 y640 w225 h30", "Exit Program")

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
profilesLaunchEditorBtn := mainGui.AddButton("x20 y680 w225 h30", "Launch Redragon Editor")
profilesExitBtn := mainGui.AddButton("x250 y680 w225 h30", "Exit Program")

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
mainGui.AddText("x20 y655 w200", "Launch Delay (ms):")
gameDelayEdit := mainGui.AddEdit("x20 y675 w150 +Border")
launchExeCheckbox := mainGui.AddCheckBox("x200 y675", "Launch with EXE")
launchExeCheckbox.Value := 1

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
mainGui.AddText("x40 y230 w120 h20", "Profile Ext:")
profileExtDrop := mainGui.AddDropDownList("x160 y228 w140 +Border", [".jmk (Mice)", ".jmr (Mice)", ".dat (Mice)", ".jml (Keyboard)", ".kbl (Keyboard)", ".kbd (Keyboard)", ".json (Keyboard)", "*.* (Other)"])
gamesSortDrop.Text := sortGamesMode
orderSortDrop.Text := sortOrder
extMap := Map("jmk", ".jmk (Mice)", "jmr", ".jmr (Mice)", "dat", ".dat (Mice)", "jml", ".jml (Keyboard)", "kbl", ".kbl (Keyboard)", "kbd", ".kbd (Keyboard)", "json", ".json (Keyboard)", "*", "*.* (Other)")
profileExtDrop.Text := extMap.Has(profileExtension) ? extMap[profileExtension] : ".jmk (Mice)"
settingsRedragonBox := mainGui.AddGroupBox("x20 y330 w460 h140", "Redragon Automation")
launchEditorBtn := mainGui.AddButton("x40 y360 w180 h26", "Launch Redragon Editor")
captureImportBtn := mainGui.AddButton("x240 y360 w180 h26", "Capture Import Button")
openProfilesBtn := mainGui.AddButton("x40 y390 w180 h26", "Open Program Folder")
testImportBtn := mainGui.AddButton("x240 y390 w180 h26", "Test Import Click")
selectRedragonExeBtn := mainGui.AddButton("x40 y420 w180 h26", "Select Redragon EXE")
settingsExitBtn := mainGui.AddButton("x295 y510 w185 h30", "Exit Program")

textColorPreview.SetFont("s11 " . "c" . SubStr(textColorCfg, 3))
for c in mainGui
    try c.Opt("Background" . SubStr(bgColorCfg, 3))

lbLauncher.OnEvent("Change", LauncherGameSelected)
lbLauncher.OnEvent("DoubleClick", LaunchSelectedGame)
launchBtn.OnEvent("Click", LaunchSelectedGame)
launcherOpenFolderBtn.OnEvent("Click", (*) => Run(profileDir))
launcherLaunchEditorBtn.OnEvent("Click", (*) => Run(redragonExe))
launcherExitBtn.OnEvent("Click", ExitWithRedragonClose)

lbProfiles.OnEvent("Change", ProfileSelected)
lbProfiles.OnEvent("DoubleClick", ImportSelectedProfile)
profilesImportBtn.OnEvent("Click", ImportSelectedProfile)
profilesOpenFolderBtn.OnEvent("Click", (*) => Run(profileDir))
profilesBackupBtn.OnEvent("Click", BackupSelectedProfile)
profilesSetFolderBtn.OnEvent("Click", SelectProfilesFolder)
profilesLaunchEditorBtn.OnEvent("Click", (*) => Run(redragonExe))
profilesExitBtn.OnEvent("Click", ExitWithRedragonClose)

lbGames.OnEvent("Change", PopulateGameFields)
editorAddBtn.OnEvent("Click", AddOrUpdateGame)
editorRemoveBtn.OnEvent("Click", RemoveSelectedGame)
editorCreateShortcutBtn.OnEvent("Click", CreateGameShortcut)
editorClearBtn.OnEvent("Click", ClearEditorFields)
editorOpenFolderBtn.OnEvent("Click", (*) => Run(profileDir))
editorExitBtn.OnEvent("Click", ExitWithRedragonClose)
editorBrowseExeBtn.OnEvent("Click", BrowseGameExe)
editorOpenExeFolderBtn.OnEvent("Click", OpenExeFolder)
editorBrowseProfileBtn.OnEvent("Click", BrowseProfileFile)

bgColorBtn.OnEvent("Click", PickBackgroundColor)
gamesSortDrop.OnEvent("Change", SortSettingsChanged)
orderSortDrop.OnEvent("Change", SortSettingsChanged)
profileExtDrop.OnEvent("Change", ProfileExtChanged)
launchEditorBtn.OnEvent("Click", (*) => Run(redragonExe))
captureImportBtn.OnEvent("Click", (*) => CaptureImportButtonCoords())
testImportBtn.OnEvent("Click", TestImportClick)
openProfilesBtn.OnEvent("Click", (*) => Run(A_ScriptDir))
selectRedragonExeBtn.OnEvent("Click", SelectRedragonExe)
settingsExitBtn.OnEvent("Click", ExitWithRedragonClose)

launcherSearchEdit.OnEvent("Change", FilterLauncherList)
profilesSearchEdit.OnEvent("Change", FilterProfilesList)
editorSearchEdit.OnEvent("Change", FilterGamesList)
launcherNotesEdit.OnEvent("Focus", LauncherNotesEditFocused)
launcherNotesEdit.OnEvent("LoseFocus", SaveLauncherNotes)
profilesNotesEdit.OnEvent("Focus", ProfilesNotesEditFocused)
profilesNotesEdit.OnEvent("LoseFocus", SaveProfileNotes)

LauncherNotesEditFocused(*) {
    global current_notes_game, lbLauncher
    current_notes_game := lbLauncher.Text
}

ProfilesNotesEditFocused(*) {
    global current_notes_profile, lbProfiles
    current_notes_profile := lbProfiles.Text
}

AddOrUpdateGame(*) {
    global gameNameEdit, gameExeEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, games
    localGameName := Trim(gameNameEdit.Value)
    exe := Trim(gameExeEdit.Value)
    prof := Trim(gameProfileEdit.Value)
    delay := Trim(gameDelayEdit.Value)
    launch := launchExeCheckbox.Value
    if (localGameName = "") {
        MsgBox("Game name cannot be empty.")
        return
    }
    added := (!games.Has(localGameName)) ? CurrentIsoTimestamp() : games[localGameName]["Added"]
    SaveGameToIni(localGameName, exe, prof, delay, launch, added)
    LoadGames()
    PopulateGameListControls()
    PopulateProfileList()
    MsgBox("Game saved.")
}

RemoveSelectedGame(*) {
    global lbGames, games
    localGameName := lbGames.Text
    if (localGameName = "") {
        MsgBox("No game selected.")
        return
    }
    RemoveGameFromIni(localGameName)
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
    global gameProfileEdit, profileDir, profileExtension
    filter := (profileExtension = "*") ? "All Files (*.*)" : "Profiles (*." . profileExtension . ")"
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
    local shortcut
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
    LaunchGameByName(localGameName)
    ExitApp
}

ImportSelectedProfile(*) {
    global lbProfiles, profileDir
    localProfileName := lbProfiles.Text
    if (localProfileName != "")
        ImportProfile(profileDir . "\" . localProfileName)
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
    global gamesFile, gamesSortDrop, orderSortDrop
    global sortGamesMode, sortOrder
    sortGamesMode := gamesSortDrop.Text
    sortOrder := orderSortDrop.Text
    IniWrite(sortGamesMode, gamesFile, "Sort", "Games")
    IniWrite(sortOrder, gamesFile, "Sort", "Order")
    PopulateGameListControls()
    PopulateProfileList()
}

ProfileExtChanged(*) {
    global profileExtension, gamesFile
    selected := profileExtDrop.Text
    if (selected = "*.* (Other)") {
        profileExtension := "*"
    } else {
        profileExtension := SubStr(selected, 2, InStr(selected, " ")-2)
    }
    IniWrite(profileExtension, gamesFile, "Config", "ProfileExtension")
    PopulateProfileList()
}

SelectRedragonExe(*) {
    global redragonExe, gamesFile
    chosen := FileSelect(3, , "Select Redragon EXE", "Executables (*.exe)")
    if (chosen != "") {
        redragonExe := chosen
        IniWrite(redragonExe, gamesFile, "Config", "RedragonExe")
        MsgBox("Redragon EXE updated to: " . redragonExe)
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

ExitWithRedragonClose(*) {
    global mainGui, gamesFile, tabs
    WinGetPos(&x, &y, , , mainGui.Hwnd)
    IniWrite(x, gamesFile, "Config", "WinX")
    IniWrite(y, gamesFile, "Config", "WinY")
    IniWrite(tabs.Value, gamesFile, "Config", "LastTab")
    if WinExist("ahk_exe OemDrv.exe")
        WinClose("ahk_exe OemDrv.exe")
    ExitApp
}

PopulateGameFields(*) {
    global lbGames, selGameLabel, gameNameEdit, gameExeEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, games
    localGameName := lbGames.Text
    selGameLabel.Text := (localGameName = "") ? "" : "Selected: " . localGameName
    if (localGameName = "") {
        gameNameEdit.Value := ""
        gameExeEdit.Value := ""
        gameProfileEdit.Value := ""
        gameDelayEdit.Value := ""
        launchExeCheckbox.Value := 1
        return
    }
    data := games[localGameName]
    gameNameEdit.Value := localGameName
    gameExeEdit.Value := data["Exe"]
    gameProfileEdit.Value := data["Profiles"]
    gameDelayEdit.Value := data["PostImportDelay"]
    launchExeCheckbox.Value := data["LaunchExe"]
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
    LoadGames()
    lbLauncher.Delete()
    lbGames.Delete()
    fullGameNames := SortGameNames(games, sortGamesMode, sortOrder)
    for n in fullGameNames {
        lbLauncher.Add([n])
        lbGames.Add([n])
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
    global lbLauncher, fullGameNames
    FilterList(lbLauncher, fullGameNames, launcherSearchEdit.Value)
}

FilterGamesList(*) {
    global lbGames, fullGameNames
    FilterList(lbGames, fullGameNames, editorSearchEdit.Value)
}

FilterProfilesList(*) {
    global lbProfiles, fullProfileNames
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
    global gameExeEdit, gameNameEdit, gameProfileEdit, gameDelayEdit, launchExeCheckbox, lbGames, selGameLabel
    gameExeEdit.Value := ""
    gameNameEdit.Value := ""
    gameProfileEdit.Value := ""
    gameDelayEdit.Value := ""
    launchExeCheckbox.Value := 0
    lbGames.Choose(0)
    selGameLabel.Text := ""
}

LoadGames()
LoadProfiles()
PopulateGameListControls()
PopulateProfileList()

winX := IniRead(gamesFile, "Config", "WinX", "")
winY := IniRead(gamesFile, "Config", "WinY", "")
if (winX != "" && winY != "")
    mainGui.Show("x" . winX . " y" . winY)
else
    mainGui.Show("Center")