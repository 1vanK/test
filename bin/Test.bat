@echo off
if exist "%~dp0Urho3DPlayer.exe" (set "DEBUG=") else (set "DEBUG=_d")
start "" "%~dp0Urho3DPlayer%DEBUG%" Scripts/Test.as  -p CoreData;Data;MyData -w  %*
