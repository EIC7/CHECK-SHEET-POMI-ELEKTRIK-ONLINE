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
