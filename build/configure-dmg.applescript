on run argv
    if (count of argv) is not 1 then error "configure-dmg: expected the mounted volume path"

    set volumeFolder to POSIX file (item 1 of argv) as alias

    tell application "Finder"
        open volumeFolder
        set volumeWindow to container window of volumeFolder
        set current view of volumeWindow to icon view
        set toolbar visible of volumeWindow to false
        set statusbar visible of volumeWindow to false
        set pathbar visible of volumeWindow to false
        set bounds of volumeWindow to {180, 120, 900, 580}

        set viewOptions to the icon view options of volumeWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 14
        set background picture of viewOptions to file ".background:ntfsmac-dmg-background.png" of volumeFolder

        set position of item "ntfsmac.app" of volumeFolder to {180, 234}
        set position of item "Applications" of volumeFolder to {540, 234}

        update volumeFolder without registering applications
        delay 2
        close volumeWindow
    end tell
end run
