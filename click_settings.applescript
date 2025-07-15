tell application "Simulator"
    activate
    delay 1
end tell

tell application "System Events"
    -- Click on Settings tab
    tell process "Simulator"
        click at {650, 1445}
    end tell
end tell
