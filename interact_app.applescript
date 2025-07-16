tell application "Simulator"
    activate
    delay 1
end tell

tell application "System Events"
    -- Type password in first field (already focused)
    keystroke "test1234"
    delay 0.5
    
    -- Tab to second field
    key code 48 -- Tab key
    delay 0.5
    
    -- Type confirm password
    keystroke "test1234"
    delay 0.5
    
    -- Press Create button
    key code 36 -- Return key
end tell
