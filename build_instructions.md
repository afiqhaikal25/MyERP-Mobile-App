# 🔧 Panduan Menyelesaikan Masalah Build App Store Connect

## **Masalah yang Dikenal Pasti:**

### 1. **Konflik Versi Build Number**
- ✅ **pubspec.yaml**: `version: 1.0.0+9` (build number = 9)
- ✅ **iOS project.pbxproj**: Sekarang menggunakan `$(FLUTTER_BUILD_NUMBER)`
- ✅ **Android build.gradle.kts**: Sekarang menggunakan `flutter.versionCode`

### 2. **MARKETING_VERSION Fixed**
- ✅ **Sebelum**: `MARKETING_VERSION = "1.0.0 "` (ada space)
- ✅ **Sekarang**: `MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)"`

## **Langkah-langkah untuk Build Baru:**

### **Langkah 1: Clean dan Rebuild**
```bash
cd /Users/zulfa/AndroidStudioProjects/ticket
flutter clean
flutter pub get
```

### **Langkah 2: Build iOS Archive**
```bash
flutter build ios --release --build-number=9
```

### **Langkah 3: Archive di Xcode**
1. Buka Xcode
2. File → Open → pilih folder `ios/Runner.xcworkspace`
3. Product → Archive
4. Tunggu archive selesai

### **Langkah 4: Upload ke App Store Connect**
1. Dalam Xcode, pilih "Distribute App"
2. Pilih "App Store Connect"
3. Pilih "Upload"
4. Pilih "Automatically manage signing"
5. Klik "Upload"

## **Pemeriksaan Tambahan:**

### **Periksa Info.plist**
- ✅ `CFBundleShortVersionString` = `$(FLUTTER_BUILD_NAME)`
- ✅ `CFBundleVersion` = `$(FLUTTER_BUILD_NUMBER)`

### **Periksa project.pbxproj**
- ✅ `CURRENT_PROJECT_VERSION` = `$(FLUTTER_BUILD_NUMBER)`
- ✅ `MARKETING_VERSION` = `$(FLUTTER_BUILD_NAME)`

## **Mengapa Build Sebelumnya Tidak Muncul:**

1. **Build Number Konflik**: iOS menggunakan build number 3, tapi pubspec.yaml menggunakan 8
2. **MARKETING_VERSION dengan Space**: Apple mungkin menolak version dengan space
3. **Tidak Sync**: iOS dan Android tidak menggunakan Flutter version numbers

## **Selepas Upload:**

1. Tunggu 5-10 minit untuk processing
2. Periksa App Store Connect → TestFlight → iOS Builds
3. Build baru sepatutnya muncul sebagai "Build 9"

## **Jika Masih Tidak Muncul:**

1. **Periksa Email**: Apple akan hantar email jika ada error
2. **Periksa Activity**: App Store Connect → Activity
3. **Tunggu Lebih Lama**: Kadang-kadang mengambil masa sehingga 30 minit

## **Command untuk Build Manual:**

```bash
# Clean project
flutter clean

# Get dependencies
flutter pub get

# Build iOS with specific build number
flutter build ios --release --build-number=9

# Atau increment build number dalam pubspec.yaml
# version: 1.0.0+10
```

## **Nota Penting:**

- ✅ Build number mesti lebih tinggi daripada yang sedia ada
- ✅ Version number mesti konsisten antara iOS dan Android
- ✅ Tiada space dalam version strings
- ✅ Gunakan Flutter build numbers, bukan hardcoded values 