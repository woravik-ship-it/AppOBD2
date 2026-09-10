#!/bin/bash
cd /home/woravik/E2_Lab/AppOBD2/build/app/outputs/flutter-apk
exec python3 -m http.server 8080 --bind 0.0.0.0
