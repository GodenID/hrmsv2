<div align="center">

# Prasasti Connect

**Sistem Informasi HRMS internal Prasasti Group — absensi, cuti, lembur,
karyawan, event, pengumuman, dan surat peringatan dalam satu genggaman.**

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Backend](https://img.shields.io/badge/Backend-Dart_Shelf-0175C2)](server/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](server/migrations/)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker&logoColor=white)](docker-compose.yml)
[![Android](https://img.shields.io/badge/Android-AAB-3DDC84?logo=android&logoColor=white)](https://github.com/GodenID/hrmsv2)
[![License](https://img.shields.io/badge/License-Private-red)](https://github.com/GodenID/hrmsv2)

[Fitur](#-fitur) · [Mulai Cepat](#-mulai-cepat) ·
[Arsitektur](#-arsitektur) · [Deploy](#-deploy) · [Keamanan](#-keamanan)

</div>

---

## ✨ Fitur

<table>
<tr>
<td width="50%">

**🕒 Absensi Cerdas**
- Clock in/out + validasi radius GPS & anti lokasi palsu
- Pengajuan luar-area + koreksi (maks. 30 hari ke belakang)
- Kalender bulanan + periode tutup buku 26–25

**🌴 Cuti & Lembur**
- Tahunan (kuota 12), izin, sakit, melahirkan otomatis 3 bulan
- Cuti bersama massal — hitung otomatis, notifikasi per karyawan
- Lembur (maks. 30 hari ke belakang, min. 1 jam)

</td>
<td width="50%">

**👥 Karyawan & Organisasi**
- Pendaftaran mandiri + consent UU PDP
- Pendaftar pertama = Super Admin otomatis
- Profil, foto, role, atasan, nonaktifkan akun

**📅 Event · 📣 Pengumuman · ⚖️ SP**
- Event + crew + ambang PO + pengingat hari-H
- Pengumuman terjadwal, tersasar divisi, laporan pembaca
- SP 1–3: eskalasi, tanda tangan, sanggahan, pencabutan

</td>
</tr>
</table>

> 🔔 Semua kejadian penting (persetujuan, akun baru, kontrak kedaluwarsa,
> hari-H event) masuk **notifikasi persisten** dengan badge belum-dibaca.

---

## 👑 Peran Pengguna

| Kemampuan | Staff | Manager | Super Admin |
|:---|:---:|:---:|:---:|
| Absen, ajukan cuti / lembur / koreksi | ✅ | ✅ | ✅ |
| Setujui pengajuan tim | — | Staff saja | Semua |
| Kelola karyawan & event | — | ✅ | ✅ |
| Cuti bersama, lokasi absen, SP, pengumuman | — | — | ✅ |

---

## 🏗️ Arsitektur

```
┌──────────────┐   HTTPS + JSON   ┌──────────────┐   SQL    ┌────────────┐
│  Flutter App │ ◄──────────────► │  Dart Shelf  │ ◄──────► │ PostgreSQL │
│    lib/      │                  │   server/    │          │ migrasi    │
└──────┬───────┘                  └──────┬───────┘          │  001 – 006 │
       │                                │                  └────────────┘
       │  presigned PUT / GET           │ SigV4
       ▼                                ▼
┌─────────────────────────────────────────────────┐
│          Penyimpanan Objek S3-Compatible         │
│   surat dokter (privat) · avatar (publik)       │
└─────────────────────────────────────────────────┘
```

---

## 🚀 Mulai Cepat

### 1️⃣ Backend — Postgres + API

```sh
docker compose up --build
curl http://localhost:8080/health   # → {"ok":true}
```

### 2️⃣ Aplikasi melawan backend lokal

```sh
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

> 📝 Daftarkan akun pertama lewat halaman **Daftar** — ia otomatis menjadi
> **Super Admin**. Pendaftar berikutnya menjadi Staff.

---

## ⚙️ Konfigurasi

<details>
<summary><b>📱 Aplikasi Flutter</b></summary>

| Define | Wajib | Keterangan |
|:---|:---:|:---|
| `API_BASE_URL` | ✅ | URL server, mis. `https://api.domain.id` |

</details>

<details>
<summary><b>🖥️ Server (environment)</b></summary>

| Variabel | Wajib | Keterangan |
|:---|:---:|:---|
| `DATABASE_URL` | ✅ | `postgres://user:pass@host:5432/db` |
| `JWT_SECRET` | ✅ | Minimal 32 karakter acak |
| `RUN_MIGRATIONS` | Sekali | `true` saat deploy pertama / ada migrasi baru |
| `S3_ENDPOINT` | File | Mis. `https://s3.contoh.id` |
| `S3_BUCKET` | File | Nama bucket yang sudah ada |
| `S3_REGION` | File | Default `ap-southeast-1` |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | File | Via secret manager — **jangan di-commit** |
| `S3_PATH_STYLE` | — | `true` = `endpoint/bucket/key` · `false` (default) = `bucket.endpoint/key` |
| `S3_AVATAR_PUBLIC` | — | `true` (default) = avatar public-read, surat tetap privat |

Tanpa env S3, upload file nonaktif secara anggun (lampiran tercatat sebagai metadata).

</details>

> 🛡️ `.env` asli, `*.jks`, dan `key.properties` **tidak pernah di-commit**
> (sudah di-`.gitignore`). Mulai dari `server/.env.example`.

---

## 📦 Deploy

<table>
<tr>
<td width="50%">

**☁️ Backend → Coolify**
1. New Resource → PostgreSQL 16
2. New Application → repo ini, root `server/`, Dockerfile
3. Isi env → Deploy → cek `/health`
4. Daftar akun pertama → matikan `RUN_MIGRATIONS`

</td>
<td width="50%">

**🤖 Android → Play Store**
```sh
flutter build appbundle --release
```
Upload `.aab` ke Play Console → Internal testing → Production.
Cadangkan `upload-keystore.jks` + `key.properties` — hilang = tak bisa update app.

</td>
</tr>
</table>

---

## 🧪 Kualitas

```sh
flutter analyze          # harus bersih
flutter test             # tanpa server
cd server && dart analyze # harus bersih
```

- ✅ Server menegakkan peran, kuota, & validasi (bukan hanya di UI)
- ✅ Jam clock & jarak GPS dihitung server (WIB)
- ✅ NIK lengkap tak pernah dikirim ke aplikasi
- ✅ Surat privat via presigned URL 15 menit · rate-limit login · sesi revocable

📖 Detail endpoint per fase → [`server/README.md`](server/README.md)

---

<div align="center">

**Dibangun dengan 💙 untuk Prasasti Group**

### Created By [Goden](https://github.com/GodenID)

*Flutter · Dart Shelf · PostgreSQL · S3-Compatible Storage · Docker*

</div>
