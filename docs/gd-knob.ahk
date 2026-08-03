#Requires AutoHotkey v2.0

svv := "C:\Program Files\SoundVolumeView\SoundVolumeView.exe"
app := "GeometryDash.exe"

F14::Run(svv ' /ChangeVolume "' app '" 1', , "Hide")   ; knob CW  = louder
F13::Run(svv ' /ChangeVolume "' app '" -1', , "Hide")  ; knob CCW = quieter
F15::Run(svv ' /Switch "' app '"', , "Hide")           ; knob press = mute toggle