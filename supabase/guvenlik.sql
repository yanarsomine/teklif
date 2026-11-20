-- 6) Güvenlik ve veri bütünlüğü (Kasım 2026)
-- Supabase > SQL Editor > New query: bu dosyanın tamamını yapıştırıp "Run" deyin. Birden çok kez çalıştırmak zararsızdır.
-- Ne yapar:
--  * Yeni açılan hesaplar "onay bekliyor" (pending) olur; yönetici onaylamadan hiçbir veriyi göremez.
--  * Kalıcı silme yalnız yöneticide; personel "çöp kutusuna" taşır (programda).
--  * Teklif numarasını veritabanı verir (aynı anda kaydeden iki kişi aynı numarayı alamaz).
--  * Her kayıt değişikliği "kimin, ne zaman, eski hali" ile docs_log tablosuna yazılır.
--  * Kur ve sıradaki numara sayacını personel değiştiremez.

-- 6.1 Roller: onay bekleyen hesap
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','staff','pending'));
alter table public.profiles alter column role set default 'pending';

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role in ('admin','staff'));
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, role) values (new.id, coalesce(new.raw_user_meta_data->>'name',''), 'pending')
  on conflict (id) do nothing;
  return new;
end; $$;

drop policy if exists "profil okuma" on public.profiles;
create policy "profil okuma" on public.profiles for select to authenticated using (id = auth.uid() or public.is_member());

-- 6.2 Kayıtlar: kim, ne zaman
alter table public.docs add column if not exists updated_by uuid;
create or replace function public.docs_touch() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := clock_timestamp();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end; $$;
drop trigger if exists docs_touch on public.docs;
create trigger docs_touch before insert or update on public.docs for each row execute function public.docs_touch();

create table if not exists public.docs_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  uid uuid default auth.uid(),
  op text not null,
  collection text not null,
  doc_id text not null,
  old_data jsonb
);
alter table public.docs_log enable row level security;
drop policy if exists "kayit izi oku" on public.docs_log;
create policy "kayit izi oku" on public.docs_log for select to authenticated using (public.is_admin());

create or replace function public.docs_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    insert into public.docs_log(op, collection, doc_id, old_data) values ('silme', old.collection, old.id, old.data);
    return old;
  elsif tg_op = 'UPDATE' then
    if old.data is distinct from new.data and new.collection <> 'counter' then
      insert into public.docs_log(op, collection, doc_id, old_data) values ('degisiklik', new.collection, new.id, old.data);
    end if;
    return new;
  else
    if new.collection <> 'counter' then
      insert into public.docs_log(op, collection, doc_id, old_data) values ('ekleme', new.collection, new.id, null);
    end if;
    return new;
  end if;
end; $$;
drop trigger if exists docs_audit on public.docs;
create trigger docs_audit after insert or update or delete on public.docs for each row execute function public.docs_audit();

-- 6.3 Okuma/yazma kuralları: yalnız onaylı üyeler; silme yalnız yönetici
drop policy if exists "herkes okur" on public.docs;
drop policy if exists "uye okur" on public.docs;
create policy "uye okur" on public.docs for select to authenticated using (public.is_member());

create or replace function public.staff_can_write(c text, i text) returns boolean
language sql stable as $$
  select c in ('quotes','musteriler') or c like 'musteriler/%' or (c = 'counter' and i in ('backup','backup-err'));
$$;
drop policy if exists "personel yazar" on public.docs;
drop policy if exists "personel ekler" on public.docs;
drop policy if exists "personel gunceller" on public.docs;
drop policy if exists "yonetici siler" on public.docs;
create policy "personel ekler" on public.docs for insert to authenticated
  with check (public.is_admin() or (public.is_member() and public.staff_can_write(collection, id)));
create policy "personel gunceller" on public.docs for update to authenticated
  using (public.is_admin() or (public.is_member() and public.staff_can_write(collection, id)))
  with check (public.is_admin() or (public.is_member() and public.staff_can_write(collection, id)));
create policy "yonetici siler" on public.docs for delete to authenticated using (public.is_admin());

-- 6.4 Teklif numarası: tek adımda ver ve sayacı ilerlet (aynı anda iki kişi aynı numarayı alamaz)
create or replace function public.next_quote_no(p_min integer default 1) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_member() then raise exception 'yetki yok'; end if;
  insert into public.docs(collection, id, data) values ('counter', 'quotes', jsonb_build_object('next', greatest(coalesce(p_min,1),1)))
  on conflict (collection, id) do nothing;
  update public.docs
     set data = jsonb_set(coalesce(data,'{}'::jsonb), '{next}', to_jsonb(greatest(coalesce((data->>'next')::int, 1), coalesce(p_min,1)) + 1))
   where collection = 'counter' and id = 'quotes'
  returning (data->>'next')::int - 1 into n;
  return n;
end; $$;
revoke all on function public.next_quote_no(integer) from public;
grant execute on function public.next_quote_no(integer) to authenticated;

-- 6.5 Dosya kovaları: yalnız onaylı üyeler; silme yalnız yönetici
drop policy if exists "resim yukle" on storage.objects;
create policy "resim yukle" on storage.objects for insert to authenticated with check (bucket_id = 'uploads' and public.is_member());

drop policy if exists "teklif pdf oku" on storage.objects;
create policy "teklif pdf oku" on storage.objects for select to authenticated using (bucket_id = 'teklifler' and public.is_member());
drop policy if exists "teklif pdf yukle" on storage.objects;
create policy "teklif pdf yukle" on storage.objects for insert to authenticated with check (bucket_id = 'teklifler' and public.is_member());
drop policy if exists "teklif pdf guncelle" on storage.objects;
create policy "teklif pdf guncelle" on storage.objects for update to authenticated using (bucket_id = 'teklifler' and public.is_member()) with check (bucket_id = 'teklifler' and public.is_member());
drop policy if exists "teklif pdf sil" on storage.objects;
create policy "teklif pdf sil" on storage.objects for delete to authenticated using (bucket_id = 'teklifler' and public.is_admin());

drop policy if exists "musteri dosya oku" on storage.objects;
create policy "musteri dosya oku" on storage.objects for select to authenticated using (bucket_id = 'musteri-dosyalari' and public.is_member());
drop policy if exists "musteri dosya yukle" on storage.objects;
create policy "musteri dosya yukle" on storage.objects for insert to authenticated with check (bucket_id = 'musteri-dosyalari' and public.is_member());
drop policy if exists "musteri dosya sil" on storage.objects;
create policy "musteri dosya sil" on storage.objects for delete to authenticated using (bucket_id = 'musteri-dosyalari' and public.is_admin());
