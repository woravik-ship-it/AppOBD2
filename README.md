# AppOBD2 — อ่านค่าจาก OBD2 ผ่าน Bluetooth (ELM327)

Flutter app เชื่อม ELM327 Bluetooth Classic (SPP) แล้ววนอ่าน Mode 01 PIDs:
RPM / Speed / Engine Load / Coolant / Intake Air / Throttle / Fuel / Battery

## ใช้อะไร
- `flutter_bluetooth_serial` — SPP ต่อ ELM327 (BLE ใช้ไม่ได้นะ ELM327 ส่วนใหญ่เป็น BT Classic)
- `permission_handler` — ขอ BT/scan/connect + location (Android 12+)
- `shared_preferences` — จำ adapter ตัวล่าสุด
- `wakelock_plus` — กันจอดับตอนขับ

## โครงไฟล์
- `lib/main.dart` — dashboard + connect + poll loop
- `lib/obd_service.dart` — SPP connect, ส่ง AT/PID รอ prompt `>`
- `lib/obd_pids.dart` — PID table + decoder ตาม SAE J1979

## วิธีใช้
1. Pair ELM327 กับมือถือใน System BT settings ก่อน (PIN มัก `1234`/`0000`)
2. เปิดแอป → Refresh → เลือก device → Connect
3. แอป init `ATZ E0 L0 S0 H0 SP0` + `ATRV` แล้ววนอ่าน PID ทีละตัวทุก ~400ms

## Build
```
cd /home/woravik/E2_Lab/AppOBD2
flutter pub get
flutter run            # ลงมือถือผ่าน USB
flutter build apk      # Truck.apk แบบ release
```

## หมายเหตุ
- Android เท่านั้น (iOS ไม่มี SPP) — `AndroidManifest` ต้องมี BLUETOOTH_* permission (flutter_bluetooth_serial จัดการให้)
- รถบางคันตอบ `NO DATA` บาง PID — ช่องนั้นโชว์ `--` (ปกติ)
- ELM327 ก๊อปจีนบางตัว init ช้า — กด Connect ซ้ำได้
