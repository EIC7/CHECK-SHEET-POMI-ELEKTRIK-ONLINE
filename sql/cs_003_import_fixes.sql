-- ============================================================================
--  cs_003 — Penyesuaian setelah memeriksa data nyata hasil export Firestore
--  (aman dijalankan berulang)
--   * cs_drafts.form_id: 2 dari 49 draft di Firestore TIDAK punya formId ->
--     kolom NOT NULL akan menggagalkan impor. Dibuat boleh kosong.
-- ============================================================================
alter table public.cs_drafts alter column form_id drop not null;
alter table public.cs_drafts alter column form_id set default '';
