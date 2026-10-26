# Prasasti Server (Shelf + PostgreSQL)

Fase 1: auth + pendaftaran. Pendaftar pertama otomatis superadmin.

## Coolify

1. Database → New Resource → PostgreSQL 16, catat `DATABASE_URL`
   (`postgres://user:pass@host:5432/prasasti`).
2. Service → New Application → dari repo ini, root `server/`,
   build type Dockerfile.
3. Env:
   - `DATABASE_URL` (dari langkah 1)
   - `JWT_SECRET` (acak ≥32 karakter)
   - `RUN_MIGRATIONS=true` (matikan setelah deploy pertama sukses)
   - `PORT=8080`
4. Deploy. Cek `GET /health` → `{"ok":true}`.
5. Daftarkan akun pertama via aplikasi / `POST /auth/register`
   → otomatis `role: superadmin`. Pendaftar berikutnya: `staff`.

## Lokal (butuh Postgres jalan)

```sh
cd server
cp .env.example .env   # isi manual, atau export env
export DATABASE_URL=postgres://prasasti:pass@localhost:5432/prasasti
export JWT_SECRET=dev_min_32_karakter_acak_1234567890
export RUN_MIGRATIONS=true
dart run bin/server.dart
```

## Flutter

```sh
# mock (default)
flutter run
# API
flutter run --dart-define=API_BASE_URL=https://api.kamu.id
```

Endpoint auth: lihat `lib/auth_handlers.dart`.

## Fase 2 — employees

- `GET /employees` (manager, superadmin)
- `GET /employees/:username`
- `POST /employees` → `{account, temporaryPassword}`
- `PUT /employees/:username`
- `PATCH /employees/:username/active` → `{active}` (nonaktif cabut semua sesi)
- `POST /employees/:username/reset-password` → `{temporaryPassword}`
- `PUT /settings/registration` (superadmin) → `{open}`

DB produksi mulai kosong — tanpa seed demo. Akun pertama daftar = superadmin.

## Fase 3 — attendance

Jam & jarak dihitung server (WIB = UTC+7). Riwayat lama TIDAK dipalsukan:
hari kerja tanpa catatan = absen (jujur, bukan demo).

- `GET /attendance/today`, `POST /attendance/clock-in`, `POST /attendance/clock-out`
  (tolak lokasi palsu, hitung haversine sendiri)
- `GET /attendance/locations`, `POST /attendance/locations`,
  `PUT /attendance/locations/:id`, `DELETE /attendance/locations/:id`
  (superadmin; minimal 1 tersisa; produksi mulai kosong — isi via API)
- `GET /attendance/month?year=&month=`, `GET /attendance/first-month`
- Koreksi: `POST /attendance/corrections`, `GET /attendance/corrections/queue`,
  `POST /attendance/corrections/:id/review`, `POST /attendance/corrections/:id/cancel`
- Luar area: `POST /attendance/out-of-area`, `GET /attendance/out-of-area/mine`,
  `GET /attendance/out-of-area/queue`, `POST /attendance/out-of-area/:id/review`,
  `POST /attendance/out-of-area/:id/cancel`

## Fase 4 — leave, overtime, notifikasi

- Cuti: `GET /leave/balance`, `GET /leave/requests`, `POST /leave/requests`
  (validasi = mock: kuota, tabrakan, lampiran sakit ≥2 hari, maks 180 hari;
  melahirkan otomatis 3 bulan sejak hari pengajuan, tanpa potong kuota),
  `POST /leave/requests/:id/cancel`, `GET /leave/queue`,
  `POST /leave/requests/:id/review` (cek sisa kuota saat setujui)
- Cuti bersama: `POST /leave/collective` (superadmin; hitung otomatis
  Senin–Jumat, lewati yg sudah tercakup; tiap karyawan dapat notifikasi
  berisi hari terpotong + sisa)
- Lembur: `GET /overtime/requests`, `POST /overtime/requests`
  (maks 30 hari ke belakang, min 1 jam, tolak bila bentrok cuti),
  `POST /overtime/requests/:id/cancel`, `GET /overtime/queue`,
  `POST /overtime/requests/:id/review`
- Notifikasi: `GET /notifications` (termasuk pengingat kontrak persisten
  id stabil), `GET /notifications/unread-count`,
  `POST /notifications/:id/read`, `POST /notifications/read-all`,
  `DELETE /notifications`
- Kalender absensi (`GET /attendance/month`) kini overlay cuti
  (disetujui = status cuti; pengajuan baru langsung tampil; tanggal akan
  datang ikut tampil bila tercakup cuti)

Sisa mock: announcements, events, warnings.

## Fase 4b — file ke S3 Onidel

- HP upload langsung ke S3 via presigned PUT (tidak lewat VPS):
  `POST /uploads/presign` → `{key, putUrl}` → PUT bytes → kirim key
- Surat dokter: `leave/{username}/…`, privat, dibuka via
  `GET /uploads/view?key=` → `{url}` presigned 15 mnt (pemilik +
  manager/superadmin pengelola). Key diverifikasi milik sendiri + wajib
  sudah ter-upload (HEAD) saat pengajuan dikirim.
- Foto profil: `avatars/{username}/…`, publik (sesuai pilihan) atau
  presigned bila `S3_AVATAR_PUBLIC=false`. Ganti foto menghapus objek lama.
- Profil: `GET /profile`, `GET /profile/photo`, `PUT /profile/photo`,
  `DELETE /profile/photo`, `POST /profile/change-password`,
  `PUT /profile/contact`
- Env: `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION` (default ap-southeast-1),
  `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_PATH_STYLE` (false = virtual-hosted),
  `S3_AVATAR_PUBLIC`. Tanpa env ini upload mati (lampiran metadata saja).

## Fase 5 — pengumuman, event, peringatan (mock terakhir habis)

- Pengumuman: `GET /announcements/feed` (pinned dulu, visibilitas
  jadwal + divisi), `POST /announcements/:id/open` (catat lihat sekali),
  `GET /announcements/:id/readers`, `POST /announcements`,
  `PUT /announcements/:id`, `DELETE /announcements/:id` (superadmin;
  lampiran S3 ikut dihapus). Lampiran ≤5 MB maks 3 via
  `POST /uploads/presign` purpose `announcement`.
- Event: ambang (`GET/PUT /events/thresholds`, manager+), kategori
  (`GET/POST/DELETE /events/categories`), CRUD event, gabung/keluar crew
  (`POST /events/:id/join`, `DELETE /events/:id/leave`), pengingat hari-H
  otomatis, notifikasi pembatalan ke crew. Nilai PO hanya untuk
  manager/superadmin.
- SP: `GET /warnings/issuable`, `GET /warnings/suggest`,
  `POST /warnings` (superadmin; kedaluwarsa +6 bulan otomatis),
  `GET /warnings`, `GET /warnings/mine`,
  `POST /warnings/:id/acknowledge|appeal|respond-appeal`,
  pengingat H-30 ke superadmin.

Mode API kini 100% server. `AppDependencies.mock` tersisa untuk
pengujian saja. Siap deploy Coolify.

## Fase 8 - rilis aplikasi (pembaruan otomatis)

- `GET /app/version` (publik, tanpa auth) > versi Android terbaru:
  `versionCode`, `versionName`, `minVersionCode`, `sha256`, `sizeBytes`,
  `notes`, `apkUrl` presigned 1 jam. `{"available":false}` bila belum ada
  rilis atau S3 mati.
- `GET /app/releases` (superadmin) > riwayat rilis.
- `POST /app/releases` (superadmin) > terbitkan versi. `versionCode` wajib
  lebih besar dari yang sudah terbit; server memverifikasi objek APK ada di
  S3 dan mencatat ukuran aslinya.
- `POST /uploads/presign` purpose `apk` (superadmin, `.apk`, maks 300 MB,
  URL berlaku 1 jam) > key `releases/...`.
- Alat terbit dari PC: `tool/publish_release.ps1` (login > presign > unggah >
  catat rilis).
