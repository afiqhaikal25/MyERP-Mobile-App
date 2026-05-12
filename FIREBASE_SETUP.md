# Firebase Setup Guide

## Masalah yang Ditemui
Server key Firebase telah terdedah di GitHub dan mungkin telah dibatalkan oleh Google untuk keselamatan.

## Langkah-langkah Penyelesaian

### 1. Dapatkan Server Key Baru
1. Pergi ke [Firebase Console](https://console.firebase.google.com/)
2. Pilih projek anda
3. Pergi ke **Project Settings** (gear icon)
4. Klik tab **Cloud Messaging**
5. Salin **Server Key** yang baru

### 2. Ganti Server Key dalam Kod
Ganti `YOUR_FIREBASE_SERVER_KEY_HERE` dalam file-file berikut dengan server key yang baru:

- `lib/firebase_messaging_service.dart` (line 95)
- `lib/main.dart` (line 497)
- `lib/odoo_service.dart` (line 1583)
- `lib/notification_service.dart` (line 339)

### 3. Konfigurasi Odoo
Pastikan server key juga dikonfigurasi dalam Odoo:
1. Pergi ke Odoo > Settings > Technical > Parameters > System Parameters
2. Cari atau tambah parameter `firebase_server_key`
3. Masukkan server key yang baru

### 4. Test FCM Token
Selepas mengganti server key, test FCM token:
1. Login ke app
2. Periksa log untuk melihat jika FCM token berjaya disimpan
3. Test push notification

## Keselamatan
- JANGAN commit server key ke GitHub lagi
- Gunakan environment variables untuk production
- Simpan server key dalam Odoo configuration, bukan dalam kod

## Troubleshooting
Jika masih mendapat error 404:
1. Pastikan server key betul
2. Periksa endpoint `/api/fcm/token` wujud di Odoo
3. Pastikan module FCM diaktifkan di Odoo
