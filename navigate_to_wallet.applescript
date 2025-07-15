tell application "Simulator"
    activate
    delay 1
end tell

tell application "System Events"
    -- Press Tab to navigate to wallet
    key code 48 -- Tab
    delay 0.5
    key code 48 -- Tab again if needed
    delay 0.5
    -- Press Enter to select
    key code 36 -- Return
end tell
