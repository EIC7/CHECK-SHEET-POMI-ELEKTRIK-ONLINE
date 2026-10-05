# Rencana migrasi Firestore → Supabase (EIC7) — RANCANGAN

Prinsip: **Firebase tidak diubah/dihapus sampai Supabase terbukti jalan sama seperti sebelumnya.**
Hanya repo org EIC7 yang disentuh. Project Supabase tujuan: `xzjayhjierilqxwucnkn` (database baru — sudah dikonfirmasi pengguna). Login: Supabase Auth (keputusan pengguna).

## Pemetaan koleksi → tabel (file: `sql/cs_001_schema_firestore_mirror.sql`)
| Firestore | Supabase | Catatan |
|---|---|---|
| `checksheets` | `cs_checksheets` | kolom inti + `data jsonb` (isi form apa adanya) |
| `approvals` | `cs_approvals` | status dibatasi 4 nilai; review/approval/returned_note = jsonb |
| `dashboard_users` | **Supabase Auth** + `cs_user_scope` | akun login = auth.users (username@pmunit7.local, sama dgn PM-UNIT-7); tabel hanya menyimpan team/area/role lama |
| `checksheet_drafts` | `cs_drafts` | id format lama dipertahankan |
| `motor_master` | `cs_motor_master` | id = slug tag |
| `weekly_dashboard/{key}` | `cs_weekly_meta` | key `eic7_weekly` / `eic7_jobarrangement` |
| `weekly_dashboard/{key}/workOrders` | `cs_weekly_work_orders` | PK (key, id) |
| `dashboard_config/registration` | `cs_config` | key `registration` |

## Fase
1. **Skema** (file SQL di atas) dijalankan di SQL Editor Supabase. RLS aktif, belum ada policy publik.
2. **Ekspor Firestore → impor Supabase** (skrip terpisah, memakai service_role di komputer Anda; ID dokumen dipertahankan; `createdAt` ISO → timestamptz; `submittedAt` {seconds,nanoseconds} → timestamptz).
3. **Foto**: base64 di dalam dokumen `checksheets` dipindah ke Supabase Storage (path disimpan di `photo_urls`), atau dibiarkan dulu di `data`.
4. **Adapter** `db-helper.js` / `approval-helper.js` / `cloud-draft.js` versi Supabase dengan kontrak fungsi yang sama (`DB.*`, `Approvals.*`), dipasang di branch/halaman uji dulu. Di fase ini policy RLS per tabel dibuat.
5. **Uji paralel**: tulis ke Firestore dan Supabase, bandingkan hasil dashboard.
6. **Cutover**: halaman membaca Supabase; Firebase tetap hidup sebagai cadangan baca-saja sampai yakin; baru dimatikan.

## Kendala / keputusan yang masih terbuka
- Login masih di sisi klien (anon key + hash tanpa salt) → RLS tidak bisa membedakan pengguna. Perlu diputuskan: pakai Supabase Auth, atau RPC login dulu.
- `dedupeLatest` (gap 24 jam) saat ini dikerjakan di browser; sementara dipertahankan, bisa dipindah ke view SQL belakangan.
- Ukuran data Firestore belum diketahui (butuh ekspor). Batas dokumen ±1 MB di Firestore tidak berlaku di Postgres, tapi baris `jsonb` besar memperlambat query.
- `PM-UNIT-7` memakai `pm_records` di Supabase dan mengirim ke Firestore lewat sinkronisasi (migrasi 009/010); setelah cutover sinkronisasi itu dihapus.
- Kode Apps Script untuk foto/PDF di Google Drive tetap ada; menghapusnya = pekerjaan terpisah (Supabase Storage).
