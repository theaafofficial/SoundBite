#!/bin/bash
echo "Starting SoundBite in Debug Mode..."
echo "Output will appear below. Please send this output to the developer if a crash occurs."
echo "--------------------------------------------------------------------------------"

lldb -o run -o bt -o quit ./SoundBite.app/Contents/MacOS/SoundBite

echo "--------------------------------------------------------------------------------"
echo "SoundBite exited with code $?"
