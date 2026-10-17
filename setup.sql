-- =====================================================================
-- SMART SCHOOL - COMPLETE DATABASE SETUP (tables + security rules + admin)
-- Paste this whole file in Supabase > SQL Editor > Run. Safe to run again.
-- =====================================================================

-- 1. TABLES -------------------------------------------------------------
create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('Admin','Teacher','Student')),
  record_id text not null,
  name text not null,
  unique (role, record_id));

create table if not exists public.students(
  id text primary key, name text not null, father_name text, cnic text,
  grade text not null, section text not null default 'A', photo text);

create table if not exists public.teachers(
  id text primary key, name text not null, father_name text, cnic text,
  assigned_subjects jsonb not null default '[]', class_teacher_of text default '');

create table if not exists public.accounts(
  id text primary key, record_id text not null, name text, role text,
  email text, status text default 'Active');

create table if not exists public.announcements(
  id bigint primary key, title text not null, date text, content text);

create table if not exists public.assignments(
  id text primary key, grade text not null, section text not null, subject text not null,
  teacher_id text not null references public.teachers(id) on delete cascade,
  day text not null, start_time text not null, end_time text not null);

create table if not exists public.marks(
  id bigint primary key,
  student_id text not null references public.students(id) on delete cascade,
  subject text, exam_title text, obtained numeric not null,
  total numeric not null check (total > 0));

create table if not exists public.student_attendance(
  date date not null,
  student_id text not null references public.students(id) on delete cascade,
  status text not null check (status in ('Present','Absent','Leave')),
  primary key (date, student_id));

create table if not exists public.teacher_attendance(
  date date not null,
  teacher_id text not null references public.teachers(id) on delete cascade,
  status text not null check (status in ('Present','Absent','Leave')),
  primary key (date, teacher_id));

-- Students and teachers may only see teacher NAMES (not CNIC etc.)
create or replace view public.teacher_names as select id, name from public.teachers;

-- 2. HELPER FUNCTIONS ---------------------------------------------------
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.my_record() returns text
language sql stable security definer set search_path = public as
$$ select record_id from public.profiles where id = auth.uid() $$;

-- teacher is assigned to this class (timetable) or is its class teacher
create or replace function public.teacher_sees_class(g text, s text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.assignments a
                  where a.teacher_id = public.my_record() and a.grade = g and a.section = s)
       or exists (select 1 from public.teachers t
                  where t.id = public.my_record() and t.class_teacher_of = g) $$;

create or replace function public.teacher_sees_student(sid text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.students st
                  where st.id = sid and public.teacher_sees_class(st.grade, st.section)) $$;

create or replace function public.student_in_class(g text, s text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.students st
                  where st.id = public.my_record() and st.grade = g and st.section = s) $$;

-- 3. SECURITY (Row Level Security) --------------------------------------
alter table public.profiles           enable row level security;
alter table public.students           enable row level security;
alter table public.teachers           enable row level security;
alter table public.accounts           enable row level security;
alter table public.announcements      enable row level security;
alter table public.assignments        enable row level security;
alter table public.marks              enable row level security;
alter table public.student_attendance enable row level security;
alter table public.teacher_attendance enable row level security;

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Admin: full access everywhere
create policy admin_all on public.profiles           for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.students           for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.teachers           for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.accounts           for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.announcements      for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.assignments        for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.marks              for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.student_attendance for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');
create policy admin_all on public.teacher_attendance for all to authenticated using (public.my_role() = 'Admin') with check (public.my_role() = 'Admin');

-- Everyone logged in: own profile, announcements
create policy own_profile on public.profiles      for select to authenticated using (id = auth.uid());
create policy read_all    on public.announcements for select to authenticated using (true);

-- Teacher: own record, own timetable, students of own classes
create policy teacher_own  on public.teachers    for select to authenticated using (public.my_role() = 'Teacher' and id = public.my_record());
create policy teacher_read on public.students    for select to authenticated using (public.my_role() = 'Teacher' and public.teacher_sees_class(grade, section));
create policy teacher_read on public.assignments for select to authenticated using (public.my_role() = 'Teacher' and teacher_id = public.my_record());
create policy teacher_read on public.teacher_attendance for select to authenticated using (public.my_role() = 'Teacher' and teacher_id = public.my_record());

-- Teacher marks student attendance: can read + add, can NOT change after saving (no update/delete policy)
create policy teacher_read   on public.student_attendance for select to authenticated using (public.my_role() = 'Teacher' and public.teacher_sees_student(student_id));
create policy teacher_insert on public.student_attendance for insert to authenticated with check (public.my_role() = 'Teacher' and public.teacher_sees_student(student_id));

-- Teacher marks/results for own students
create policy teacher_read   on public.marks for select to authenticated using (public.my_role() = 'Teacher' and public.teacher_sees_student(student_id));
create policy teacher_insert on public.marks for insert to authenticated with check (public.my_role() = 'Teacher' and public.teacher_sees_student(student_id));
create policy teacher_delete on public.marks for delete to authenticated using (public.my_role() = 'Teacher' and public.teacher_sees_student(student_id));

-- Student: only own data + own class timetable
create policy student_read on public.students           for select to authenticated using (public.my_role() = 'Student' and id = public.my_record());
create policy student_read on public.assignments        for select to authenticated using (public.my_role() = 'Student' and public.student_in_class(grade, section));
create policy student_read on public.marks              for select to authenticated using (public.my_role() = 'Student' and student_id = public.my_record());
create policy student_read on public.student_attendance for select to authenticated using (public.my_role() = 'Student' and student_id = public.my_record());

-- 4. ADMINISTRATOR (the ONLY account that exists at the start) ---------
-- First create the admin user: Authentication > Users > Add user
-- (same email as below, tick "Auto Confirm User"), then run this file again.
do $$
declare
  v_email text := 'defendercyber759@gmail.com';      -- <- admin email
  v_name  text := 'Administrator';       -- <- admin name
  v_id    uuid;
begin
  select id into v_id from auth.users where email = v_email;
  if v_id is null then
    raise notice 'Admin user % not found. Create it in Authentication > Users, then run this file again.', v_email;
    return;
  end if;
  insert into public.profiles (id, role, record_id, name)
    values (v_id, 'Admin', 'admin', v_name) on conflict (id) do nothing;
  insert into public.accounts (id, record_id, name, role, email, status)
    values ('ACC-ADMIN', 'admin', v_name, 'Admin', v_email, 'Active') on conflict (id) do nothing;
end $$;

-- 5. ADMIN-ONLY ACCOUNT FUNCTIONS (used when the Vercel function is unavailable)
-- Only a logged-in Administrator can run these (checked inside the function).
create or replace function public.admin_create_user(p_role text, p_record_id text, p_password text)
returns void language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(p_record_id) || '@school.local';
  v_name text;
begin
  if public.my_role() is distinct from 'Admin' then raise exception 'Administrator access only.'; end if;
  if p_role not in ('Student','Teacher') then raise exception 'Invalid role.'; end if;
  if length(coalesce(p_password,'')) < 6 then raise exception 'Password must be at least 6 characters.'; end if;
  if p_role = 'Student' then select name into v_name from public.students where id = p_record_id;
  else select name into v_name from public.teachers where id = p_record_id; end if;
  if v_name is null then raise exception '% record % does not exist.', p_role, p_record_id; end if;
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'A login for % already exists.', p_record_id; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, jsonb_build_object('sub', v_id::text, 'email', v_email),
    'email', v_id::text, now(), now(), now());

  insert into public.profiles (id, role, record_id, name) values (v_id, p_role, p_record_id, v_name);
end $$;

create or replace function public.admin_delete_user(p_role text, p_record_id text)
returns void language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if public.my_role() is distinct from 'Admin' then raise exception 'Administrator access only.'; end if;
  if p_role not in ('Student','Teacher') then raise exception 'Invalid role.'; end if;
  delete from auth.users where id in
    (select id from public.profiles where role = p_role and record_id = p_record_id);
end $$;

revoke all on function public.admin_create_user(text,text,text) from public, anon;
revoke all on function public.admin_delete_user(text,text)      from public, anon;
grant execute on function public.admin_create_user(text,text,text) to authenticated;
grant execute on function public.admin_delete_user(text,text)      to authenticated;
notify pgrst, 'reload schema';

-- 6. OPTIONAL: remove the OLD demo data (only if you ran the earlier version)
-- Remove the two dashes in front of the lines below and run them ONCE.
-- Also delete any demo login users in Authentication > Users (TCH-101, STD-112 ...).
-- delete from public.marks             where id in (1,2);
-- delete from public.announcements     where id in (1,2);
-- delete from public.assignments       where id like 'ASG-DEMO-%';
-- delete from public.accounts          where id in ('ACC-01','ACC-02','ACC-03');
-- delete from public.teachers          where id in ('TCH-101','TCH-102','TCH-103');
-- delete from public.students          where id in ('STD-101','STD-102','STD-103','STD-104','STD-105','STD-106','STD-107','STD-108','STD-109','STD-110','STD-111','STD-112');
