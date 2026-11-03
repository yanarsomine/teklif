-- Yanar Şömine Teklif — Supabase kurulumu
-- Supabase > SQL Editor > New query: bu dosyanın tamamını yapıştırıp "Run" deyin.

-- 1) Kullanıcı rolleri
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text default '',
  role text not null default 'staff' check (role in ('admin','staff'))
);
alter table public.profiles enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

drop policy if exists "profil okuma" on public.profiles;
create policy "profil okuma" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "profil yonetimi" on public.profiles;
create policy "profil yonetimi" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Yeni kullanıcıya otomatik personel profili
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, role) values (new.id, coalesce(new.raw_user_meta_data->>'name',''), 'staff')
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- 2) Program verileri (teklifler, ayarlar, fiyatlar, özel ürünler, kur)
create table if not exists public.docs (
  collection text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (collection, id)
);
alter table public.docs enable row level security;

drop policy if exists "herkes okur" on public.docs;
create policy "herkes okur" on public.docs for select to authenticated using (true);

-- Personel: teklif ekleyip düzenleyebilir, kur ve numara sayacını günceller
drop policy if exists "personel yazar" on public.docs;
create policy "personel yazar" on public.docs for all to authenticated
  using (collection in ('quotes','counter') or public.is_admin())
  with check (collection in ('quotes','counter') or public.is_admin());

-- Canlı güncelleme (bir kişinin kaydettiği teklif diğerlerinde anında görünür)
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- 3) Yüklenen resimler
insert into storage.buckets (id, name, public) values ('uploads','uploads', true)
on conflict (id) do nothing;
drop policy if exists "resim yukle" on storage.objects;
create policy "resim yukle" on storage.objects for insert to authenticated with check (bucket_id = 'uploads');
drop policy if exists "resim oku" on storage.objects;
create policy "resim oku" on storage.objects for select using (bucket_id = 'uploads');
drop policy if exists "resim sil" on storage.objects;
create policy "resim sil" on storage.objects for delete to authenticated using (bucket_id = 'uploads' and public.is_admin());
