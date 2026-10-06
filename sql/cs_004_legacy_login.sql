-- ============================================================================
--  cs_004 — Pindah login lama (SHA-256 Firestore) ke Supabase Auth saat LOGIN PERTAMA
--  Aman dijalankan berulang. Jalankan HANYA di project xzjayhjierilqxwucnkn.
--
--  Alur:
--   1. Skrip impor pengguna (komputer Anda) membuat akun Auth lewat API resmi dengan
--      password acak yang tidak diketahui siapa pun, dan mengisi tabel di bawah dengan
--      hash lama (state='pending').
--   2. Saat pengguna login pertama, aplikasi memanggil cs_migrate_legacy_login(username, password).
--      Bila SHA-256(password) = hash lama -> password akun Auth diganti jadi password itu
--      (bcrypt), hash lama DIHAPUS, lalu login Auth biasa berjalan.
--   3. Akun yang SUDAH ada di Supabase sebelum impor (mis. dari PM-UNIT-7) ditandai
--      state='existing_account' dan password-nya TIDAK pernah disentuh.
--  Tabel ini tidak bisa dibaca/ditulis dari browser (RLS aktif, tanpa policy).
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.cs_legacy_credentials (
  username        text primary key,                       -- huruf kecil
  auth_user_id    uuid not null references auth.users(id) on delete cascade,
  password_sha256 text,                                   -- NULL setelah dimigrasi / untuk existing_account
  state           text not null default 'pending'
                  check (state in ('pending','migrated','existing_account')),
  fail_count      integer not null default 0,
  last_fail_at    timestamptz,
  migrated_at     timestamptz,
  created_at      timestamptz not null default now()
);
alter table public.cs_legacy_credentials enable row level security;
revoke all on public.cs_legacy_credentials from anon, authenticated;

-- Mengembalikan true HANYA bila password lama benar & akun baru saja dimigrasi.
-- (false untuk semua kasus lain, tanpa membedakan alasan -> tidak membocorkan ada/tidaknya user)
create or replace function public.cs_migrate_legacy_login(p_username text, p_password text)
returns boolean
language plpgsql security definer
set search_path = public, extensions, auth, pg_catalog
as $$
declare
  v_user text := lower(btrim(coalesce(p_username, '')));
  r      public.cs_legacy_credentials%rowtype;
begin
  if v_user = '' or coalesce(p_password, '') = '' then return false; end if;

  select * into r from public.cs_legacy_credentials where username = v_user for update;
  if not found or r.state <> 'pending' or r.password_sha256 is null then return false; end if;

  -- pembatas percobaan: 8 salah berturut-turut -> kunci 15 menit
  if r.fail_count >= 8 and r.last_fail_at > now() - interval '15 minutes' then return false; end if;

  if encode(extensions.digest(convert_to(p_password, 'UTF8'), 'sha256'), 'hex') = r.password_sha256 then
    update auth.users
       set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
           updated_at = now()
     where id = r.auth_user_id;
    update public.cs_legacy_credentials
       set state = 'migrated', password_sha256 = null, migrated_at = now(), fail_count = 0, last_fail_at = null
     where username = v_user;
    return true;
  end if;

  update public.cs_legacy_credentials
     set fail_count = case when last_fail_at is not null and last_fail_at <= now() - interval '15 minutes' then 1 else fail_count + 1 end,
         last_fail_at = now()
   where username = v_user;
  return false;
end;
$$;

revoke all on function public.cs_migrate_legacy_login(text, text) from public;
grant execute on function public.cs_migrate_legacy_login(text, text) to anon, authenticated;

-- pantauan (jalankan manual): berapa yang sudah pindah?
--   select state, count(*) from public.cs_legacy_credentials group by 1;
-- setelah SEMUA pengguna aktif sudah 'migrated', hapus sisa hash:
--   update public.cs_legacy_credentials set password_sha256 = null;
