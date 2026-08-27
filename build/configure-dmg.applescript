on run argv
    if (count of argv) is not 10 then error "configure-dmg: expected volume, website name, positions, and icon/text sizes"

    set volumeFolder to POSIX file (item 1 of argv) as alias
    set websiteName to item 2 of argv
    set appX to (item 3 of argv) as integer
    set appY to (item 4 of argv) as integer
    set applicationsX to (item 5 of argv) as integer
    set applicationsY to (item 6 of argv) as integer
    set websiteX to (item 7 of argv) as integer
    set websiteY to (item 8 of argv) as integer
    set finderIconSize to (item 9 of argv) as integer
    set finderTextSize to (item 10 of argv) as integer

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
        set icon size of viewOptions to finderIconSize
        set text size of viewOptions to finderTextSize
        set background picture of viewOptions to file ".background:ntfsmac-dmg-background.png" of volumeFolder

        set position of item "ntfsmac.app" of volumeFolder to {appX, appY}
        set position of item "Applications" of volumeFolder to {applicationsX, applicationsY}
        set position of item websiteName of volumeFolder to {websiteX, websiteY}

        update volumeFolder without registering applications
        delay 2
        close volumeWindow
    end tell
end run
