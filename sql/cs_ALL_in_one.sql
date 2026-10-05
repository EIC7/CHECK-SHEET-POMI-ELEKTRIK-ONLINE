-- ============================================================================
--  cs_ALL — SEMUA SKEMA SEKALIGUS (cs_001 + cs_002 + cs_003), urut & aman diulang
--
--  JALANKAN HANYA di project Supabase:   xzjayhjierilqxwucnkn
--  (cek alamat browser: supabase.com/dashboard/project/xzjayhjierilqxwucnkn/...)
--
--  Hasil: 10 tabel berawalan cs_ (RLS aktif, belum ada policy), tidak menyentuh
--  tabel lain. Peringatan "destructive" di dashboard itu wajar (ada
--  "drop trigger/constraint if exists" -> hanya menimpa aturan milik tabel cs_).
-- ============================================================================


-- ################################ cs_001_schema_firestore_mirror.sql ################################
-- ============================================================================
--  cs_001 — Skema Supabase "cermin" 8 koleksi Firestore (project database-eic7)
--  Repo: EIC7/CHECK-SHEET-POMI-ELEKTRIK-ONLINE (+ PM-UNIT-7 untuk approvals)
--
--  STATUS: RANCANGAN — BELUM dijalankan, BELUM ada di repo. Aman dijalankan
--  berulang kali (IF NOT EXISTS). Tidak menyentuh tabel pm_records/pm_profiles
--  yang sudah ada; semua tabel baru berawalan "cs_".
--
--  Prinsip fase 1 (sesuai rencana): Supabase disiapkan & diisi dulu, Firebase
--  TIDAK diubah. Halaman belum dipindah ke Supabase.
--   * id tetap TEXT = ID dokumen Firestore (jejak asal, mudah dicocokkan/di-rollback)
--   * kolom inti dijadikan kolom beneran (untuk filter/sort/index)
--   * sisa isi form yang bentuknya beda-beda tiap check sheet -> kolom jsonb "data"
--   * RLS AKTIF di semua tabel TANPA policy publik (default tolak semua).
--     Impor data memakai service_role (di mesin Anda, JANGAN di repo/browser).
--     Policy untuk browser baru dibuat saat fase adapter, per tabel (lihat catatan).
-- ============================================================================

create extension if not exists pgcrypto;

-- trigger umum: isi updated_at otomatis
create or replace function public.cs_touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

-- ───────────────────────── 1. checksheets ─────────────────────────
create table if not exists public.cs_checksheets (
  id              text primary key default gen_random_uuid()::text,  -- = id dokumen Firestore
  asset_tag       text,
  wo_number       text,
  execution_date  text,          -- Firestore menyimpan teks bebas dari form; jangan dipaksa date
  overall_status  text,
  form_id         text,          -- mis. nama file / jenis check sheet bila ada di dokumen
  photo_urls      jsonb,         -- patch dari DB.attachFiles()
  pdf_url         text,
  data            jsonb not null default '{}'::jsonb,   -- SELURUH dokumen asli (apa adanya)
  created_at      timestamptz not null default now(),   -- dari field createdAt (ISO string)
  submitted_at    timestamptz,                          -- dari serverTimestamp()
  updated_at      timestamptz
);
create index if not exists cs_checksheets_created_idx  on public.cs_checksheets (created_at desc);
create index if not exists cs_checksheets_asset_idx    on public.cs_checksheets (asset_tag);
create index if not exists cs_checksheets_status_idx   on public.cs_checksheets (overall_status);
-- dukung dedupeLatest (asset_tag + wo_number + execution_date, urut waktu)
create index if not exists cs_checksheets_dedupe_idx   on public.cs_checksheets (asset_tag, wo_number, execution_date, created_at);

-- ───────────────────────── 2. approvals ─────────────────────────
create table if not exists public.cs_approvals (
  id              text primary key default gen_random_uuid()::text,
  checksheet_id   text,          -- SENGAJA tanpa FK: Firestore tidak punya FK & checksheet bisa dihapus lebih dulu
  asset_tag       text not null default '',
  asset_name      text not null default '',
  checksheet_file text not null default '',
  submitted_by    text not null default '',
  revision_of     text,          -- id approvals yang digantikan
  team            text,
  area            text,
  src             text,
  status          text not null default 'submitted'
                  check (status in ('submitted','reviewed','approved','returned_to_technician')),
  review          jsonb,         -- {comments, recommendations, signature, reviewedBy, reviewedAt, auto}
  approval        jsonb,         -- {notes, signature, approvedBy, approvedAt}
  returned_note   jsonb,         -- {note, by, stage, returnedAt}
  photos_skipped  jsonb,
  final_pdf_url   text,
  data            jsonb not null default '{}'::jsonb,   -- field lain yang tidak dikenal (agar tidak ada yang hilang)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists cs_approvals_created_idx    on public.cs_approvals (created_at desc);
create index if not exists cs_approvals_status_idx     on public.cs_approvals (status);
create index if not exists cs_approvals_checksheet_idx on public.cs_approvals (checksheet_id, created_at desc);
create index if not exists cs_approvals_team_area_idx  on public.cs_approvals (team, area);
drop trigger if exists cs_approvals_touch on public.cs_approvals;
create trigger cs_approvals_touch before update on public.cs_approvals
  for each row execute function public.cs_touch_updated_at();

-- ───────────────────────── 3. dashboard_users → Supabase Auth ─────────────────────────
-- KEPUTUSAN: login pindah ke Supabase Auth (bukan tabel password sendiri).
-- Akun login = auth.users (sama seperti PM-UNIT-7: username -> email internal
-- "<username>@pmunit7.local"); peran PM-UNIT-7 sudah ada di tabel pm_profiles.
-- Tabel ini HANYA menyimpan data cakupan review milik check sheet (team/area/
-- level/peran lama Firestore), terhubung ke akun Auth yang sama -> 1 login
-- untuk PM-UNIT-7 dan check sheet.
-- Hash SHA-256 lama TIDAK dibawa (tidak bisa dipakai di Auth & tidak aman);
-- pengguna dibuatkan akun Auth dengan password sementara lalu ganti sendiri.
create table if not exists public.cs_user_scope (
  id               uuid primary key references auth.users(id) on delete cascade,
  username         text not null,
  legacy_role      text not null default 'viewer',   -- role teks bebas dari dashboard_users
  team             text,
  area             jsonb,                            -- array area
  data             jsonb not null default '{}'::jsonb,   -- field tambahan (level, nama lengkap, dll.)
  legacy_firestore_id text,                          -- id dokumen dashboard_users asal
  team_updated_at  timestamptz,
  created_at       timestamptz not null default now()
);
create unique index if not exists cs_user_scope_username_uq on public.cs_user_scope (lower(username));

-- ───────────────────────── 4. checksheet_drafts ─────────────────────────
create table if not exists public.cs_drafts (
  id          text primary key,            -- format Firestore: <formId>_<waktu>_<acak>
  form_id     text not null,
  asset_tag   text not null default 'NO-TAG',
  asset_name  text not null default '',
  frequency   text not null default '',
  device      text,
  data        jsonb not null default '{}'::jsonb,       -- payload lengkap (inputValues, foto, dst.)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cs_drafts_asset_idx on public.cs_drafts (asset_tag);
create index if not exists cs_drafts_form_idx  on public.cs_drafts (form_id);

-- ───────────────────────── 5. motor_master ─────────────────────────
create table if not exists public.cs_motor_master (
  id          text primary key,            -- slug dari tag (mmSlug)
  tag         text,
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
create index if not exists cs_motor_master_tag_idx on public.cs_motor_master (tag);

-- ───────────── 6+7. weekly_dashboard (+ subkoleksi workOrders) ─────────────
create table if not exists public.cs_weekly_meta (
  key         text primary key,            -- 'eic7_weekly' | 'eic7_jobarrangement'
  period      text not null default '',
  rec_notes   text not null default '',
  updated_at  timestamptz not null default now()
);
create table if not exists public.cs_weekly_work_orders (
  key         text not null references public.cs_weekly_meta(key) on delete cascade,
  id          text not null,               -- id dokumen WO di Firestore
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  primary key (key, id)
);

-- ───────────────────────── 8. dashboard_config ─────────────────────────
create table if not exists public.cs_config (
  key         text primary key,            -- mis. 'registration'
  value       jsonb not null default '{}'::jsonb,       -- mis. {"code": "..."}
  updated_at  timestamptz not null default now()
);

-- ───────────────────────── RLS: tolak semua dulu ─────────────────────────
alter table public.cs_checksheets        enable row level security;
alter table public.cs_approvals          enable row level security;
alter table public.cs_user_scope         enable row level security;
alter table public.cs_drafts             enable row level security;
alter table public.cs_motor_master       enable row level security;
alter table public.cs_weekly_meta        enable row level security;
alter table public.cs_weekly_work_orders enable row level security;
alter table public.cs_config             enable row level security;
-- (sengaja TIDAK ada "create policy" di file ini. Lihat catatan fase adapter.)


-- ################################ cs_002_additions.sql ################################
-- ============================================================================
--  cs_002 — Tambahan setelah cs_001 (aman dijalankan berulang)
--   1. approvals.status: tambah nilai 'revised' (dipakai approval-helper.js &
--      diizinkan di firestore.rules, tapi belum ada di cs_001 -> impor akan GAGAL tanpa ini)
--   2. tabel baru untuk 2 koleksi yang ada di versi terbaru aplikasi:
--      project_schedules (Project_Progress_Monitor.html), feedback_reports
--      (Feedback_Reports.html + feedback-widget.js)
--  RLS aktif, tanpa policy (tolak semua dulu), sama seperti cs_001.
-- ============================================================================

alter table public.cs_approvals drop constraint if exists cs_approvals_status_check;
alter table public.cs_approvals add constraint cs_approvals_status_check
  check (status in ('submitted','reviewed','approved','returned_to_technician','revised'));

-- project_schedules: kunci optimistik "rev" (naik tiap simpan), pemilik di owner.user
create table if not exists public.cs_project_schedules (
  id          text primary key,
  name        text,
  rev         integer not null default 0,
  team        text,
  area        text,
  owner       jsonb,                                 -- {user, name}
  tasks       jsonb not null default '[]'::jsonb,
  data        jsonb not null default '{}'::jsonb,    -- sisa field dokumen
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cs_project_schedules_team_idx on public.cs_project_schedules (team, area);

-- feedback_reports: status baru|ditinjau|dikerjakan|selesai|ditolak
create table if not exists public.cs_feedback_reports (
  id          text primary key,
  status      text not null default 'baru'
              check (status in ('baru','ditinjau','dikerjakan','selesai','ditolak')),
  title       text,
  description text,
  data        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cs_feedback_reports_created_idx on public.cs_feedback_reports (created_at desc);
create index if not exists cs_feedback_reports_status_idx  on public.cs_feedback_reports (status);

alter table public.cs_project_schedules enable row level security;
alter table public.cs_feedback_reports  enable row level security;


-- ################################ cs_003_import_fixes.sql ################################
-- ============================================================================
--  cs_003 — Penyesuaian setelah memeriksa data nyata hasil export Firestore
--  (aman dijalankan berulang)
--   * cs_drafts.form_id: 2 dari 49 draft di Firestore TIDAK punya formId ->
--     kolom NOT NULL akan menggagalkan impor. Dibuat boleh kosong.
-- ============================================================================
alter table public.cs_drafts alter column form_id drop not null;
alter table public.cs_drafts alter column form_id set default '';


-- ################################ penutup ################################
-- muat ulang cache skema API agar tabel langsung terbaca
notify pgrst, 'reload schema';

-- PENGECEKAN (jalankan terpisah setelah di atas sukses): harus 10 baris, rls_aktif = true semua
-- select table_name,
--        (select relrowsecurity from pg_class where oid = ('public.' || table_name)::regclass) as rls_aktif
-- from information_schema.tables
-- where table_schema = 'public' and table_name like 'cs\_%' order by 1;
