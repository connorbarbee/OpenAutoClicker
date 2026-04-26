# Open AutoClicker

A simple, open-source Windows auto clicker with a clean local GUI.

Open AutoClicker lets you repeat mouse or keyboard inputs with a bindable toggle hotkey, configurable run duration, and adjustable interval. It runs entirely on your machine and includes no telemetry, networking, analytics, update checks, or external packages.

## Features

- Clean black-and-white Windows GUI
- Bindable mouse and keyboard input
- Supports Mouse1–Mouse5
- Bindable start/stop hotkey
- Run duration from 1 to 60 minutes
- Adjustable interval in milliseconds
- Automatically pauses mouse clicking while the cursor is over the app window
- Fully local PowerShell/WinForms implementation
- No telemetry, networking, analytics, update checks, or external dependencies

## Requirements

- Windows
- Windows PowerShell 5.1 or newer

## Run

Double-click:

```bat
Start-AutoClicker.bat

Or run manually: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutoClicker.ps1
