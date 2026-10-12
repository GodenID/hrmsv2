# Prasasti Connect

Aplikasi HRMS internal Prasasti Group — absensi, cuti, lembur, karyawan,
event, pengumuman, dan surat peringatan dalam satu genggaman.

| | |
|---|---|
| **Aplikasi** | Flutter (Android, iOS, Web, Desktop) |
| **Backend** | Dart Shelf + PostgreSQL |
| **File** | Penyimpanan objek S3-compatible (presigned URL) |
| **Deploy** | Docker · Docker Compose · Coolify |

---

## Daftar isi

- [Fitur](#fitur)
- [Peran pengguna](#peran-pengguna)
- [Arsitektur](#arsitektur)
- [Jalankan lokal](#jalankan-lokal)
- [Konfigurasi](#konfigurasi)
- [Deploy](#deploy)
- [Pengujian](#pengujian)
- [Keamanan](#keamanan)

---

## Fitur

### Absensi
- Clock in / clock out dengan validasi radius lokasi (GPS) + anti lokasi palsu
- Pengajuan luar-area (di luar radius) dengan alasan, perlu persetujuan
- Koreksi absensi (maks. 30 hari ke belakang) dengan alur setuju/tolak
- Kalender absensi bulanan + periode tutup buku 26–25
- Kelola titik & radius lokasi absen (Super Admin)

### Cuti & lembur
- Cuti tahunan (kuota 12), izin, sakit, cuti melahirkan otomatis 3 bulan
- Saldo dihitung per pengguna, opsi terkunci saat kuota habis
- Cuti bersama massal oleh Super Admin — hari terhitung otomatis (Senin–Jumat),
  tiap karyawan menerima notifikasi pemotongan + sisa cuti
- Lembur (maks. 30 hari ke belakang, min. 1 jam, tolak bila bentrok cuti)

### Karyawan & organisasi
- Pendaftaran mandiri + persetujuan privasi (UU PDP)
- **Pendaftar pertama otomatis menjadi Super Admin**
- Kelola akun, role, atasan, nonaktifkan, reset password
- Profil + foto profil, ganti password, ubah kontak

### Event, pengumuman, peringatan
- Event dengan kategori, nilai & ambang PO, pendaftaran crew, pengingat hari-H
- Pengumuman terjadwal + tersasar per divisi + laporan siapa sudah membaca
- Surat peringatan SP 1–3: eskalasi otomatis, tanda tangan / tolak bersaksi,
  sanggahan, pencabutan, pengingat kedaluwarsa

### Notifikasi
- Persetujuan, penolakan, akun baru, kontrak kedaluwarsa, hari-H event —
  persisten di database dengan badge belum-dibaca.

---

## Peran pengguna

| Kemampuan | Staff | Manager | Super Admin |
|---|---|---|---|
| Absen, ajukan cuti/lembur/koreksi | ✅ | ✅ | ✅ |
| Setujui pengajuan tim | — | Staff saja | Semua |
| Kelola karyawan & event | — | ✅ | ✅ |
| Potong cuti bersama, lokasi absen, SP, pengumuman | — | — | ✅ |
| Pendaftar pertama | — | — | ✅ otomatis |

---

## Arsitektur

```
┌──────────────┐   HTTPS/JSON    ┌──────────────┐   SQL    ┌────────────┐
│  Flutter App │ ◄────────────► │ Dart Shelf   │ ◄──────► │ PostgreSQL │
│  lib/        │                 │ server/      │          │ migrasi    │
└──────┬───────┘                 └──────┬───────┘          │ 001–006    │
       │                              │                  └────────────┘
       │ presigned PUT/GET             │ SigV4
       ▼                              ▼
┌──────────────────────────────────────────────┐
│        Penyimpanan objek S3-compatible        │
│  surat dokter (privat) · avatar (publik)     │
└──────────────────────────────────────────────┘
```

- **Tanpa backend** (`flutter run`): aplikasi memakai data mock lokal —
  cocok untuk pengembangan UI.
- **Dengan backend** (`--dart-define=API_BASE_URL=...`): seluruh repository
  bicara ke API. File diunggah HP → S3 langsung via presigned URL
  (tidak lewat VPS).

Struktur penting:

| Path | Isi |
|---|---|
| `lib/` | Aplikasi Flutter (fitur per folder di `lib/features`) |
| `lib/data/api/` | Klien REST (satu file per domain) |
| `lib/data/mock/` | Data mock — **hanya untuk pengujian** |
| `server/` | Backend Dart Shelf (`bin/`, `lib/`, `migrations/`) |
| `docker-compose.yml` | Postgres + server untuk lokal |
| `android/` | Konfigurasi Android (`applicationId: com.prasasti.connect`) |

---

## Jalankan lokal

### 1. Aplikasi (mode mock)

```sh
flutter pub get
flutter run
```

Login demo — password semua: `Prasasti@2026`

| Username | Peran |
|---|---|
| `andi.pratama` | Super Admin |
| `siti.rahma` | Manager |
| `budi.santoso` | Staff |

### 2. Backend + database

```sh
# Terminal 1 — Postgres + server
docker compose up --build

# (opsional) tanpa docker: butuh Postgres 16 lokal
cd server
export DATABASE_URL=postgres://prasasti:pass@localhost:5432/prasasti
export JWT_SECRET=dev_min_32_karakter_acak_1234567890
export RUN_MIGRATIONS=true
dart run bin/server.dart
```

Cek: `GET http://localhost:8080/health` → `{"ok":true}`

### 3. Aplikasi melawan backend lokal

```sh
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

> Daftarkan akun pertama lewat halaman **Daftar** — ia otomatis menjadi
> Super Admin. Pendaftar berikutnya menjadi Staff.

---

## Konfigurasi

### Aplikasi Flutter

| Define | Wajib | Keterangan |
|---|---|---|
| `API_BASE_URL` | Tidak | Kosong = mode mock. Diisi = mode API, mis. `https://api.domain.id` |

### Server (environment)

| Variabel | Wajib | Keterangan |
|---|---|---|
| `PORT` | Tidak | Default `8080` |
| `DATABASE_URL` | Ya | `postgres://user:pass@host:5432/db` |
| `JWT_SECRET` | Ya | Minimal 32 karakter acak |
| `RUN_MIGRATIONS` | Sekali | `true` saat deploy pertama / ada migrasi baru |
| `S3_ENDPOINT` | Untuk file | Mis. `https://s3.contoh.id` |
| `S3_BUCKET` | Untuk file | Nama bucket yang sudah ada |
| `S3_REGION` | Untuk file | Default `ap-southeast-1` |
| `S3_ACCESS_KEY` | Untuk file | Via env / secret manager, **jangan di-commit** |
| `S3_SECRET_KEY` | Untuk file | Via env / secret manager, **jangan di-commit** |
| `S3_PATH_STYLE` | Tidak | `true` = `endpoint/bucket/key`, `false` (default) = `bucket.endpoint/key` |
| `S3_AVATAR_PUBLIC` | Tidak | `true` (default) = avatar public-read, surat privat |

Tanpa env S3, upload file nonaktif anggun (lampiran tercatat sebagai metadata).

Salin `server/.env.example` sebagai titik awal — **jangan pernah commit file
`.env` asli, `*.jks`, atau `key.properties`** (sudah di-`.gitignore`).

---

## Deploy

### Backend ke Coolify

1. **Database** → New Resource → PostgreSQL 16 → catat `DATABASE_URL`.
2. **Service** → New Application → repo ini, root `server/`, build Dockerfile.
3. Isi env (`DATABASE_URL`, `JWT_SECRET`, `RUN_MIGRATIONS=true`, `S3_*`).
4. Deploy → cek `/health` → daftar akun pertama → matikan `RUN_MIGRATIONS`.

### Android (Play Store)

```sh
flutter build appbundle --release
```

File `build/app/outputs/bundle/release/app-release.aab` diunggah ke
Play Console → Internal testing → Production. Upload key ada di
`android/app/upload-keystore.jks` + `android/key.properties` —
**cadangkan keduanya** (hilang = tidak bisa update aplikasi).

---

## Pengujian

```sh
flutter analyze          # harus bersih
flutter test             # 157+ test (mock, tanpa server)
cd server && dart analyze
```

---

## Keamanan

- Password di-hash (bcrypt), sesi JWT 30 hari tersimpan di DB dan bisa dicabut
- Login & lupa-password dibatasi laju (5x gagal → kunci 15 menit)
- Jam clock & jarak lokasi dihitung server (WIB), bukan dari perangkat
- Aturan peran ditegakkan di server, bukan hanya disembunyikan di UI
- NIK lengkap tidak pernah dikirim ke aplikasi (hanya versi tersamar)
- Surat dokter privat via presigned URL kedaluwarsa 15 menit

---

Dokumen teknis backend (daftar endpoint per fase): [`server/README.md`](server/README.md).
