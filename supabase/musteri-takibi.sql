-- 5) Müşteri takibi (müşteri dosyaları, işler, keşif/teklif dosyaları)
-- Personel müşteri kayıtlarını ekleyip düzenleyebilir
drop policy if exists "personel yazar" on public.docs;
create policy "personel yazar" on public.docs for all to authenticated
  using (collection in ('quotes','counter','musteriler') or collection like 'musteriler/%' or public.is_admin())
  with check (collection in ('quotes','counter','musteriler') or collection like 'musteriler/%' or public.is_admin());
-- Dosyayı kimin eklediği görünsün diye personel isimleri okunabilir
drop policy if exists "profil okuma" on public.profiles;
create policy "profil okuma" on public.profiles for select to authenticated using (true);
-- Müşteri dosyaları için gizli kova (yalnızca giriş yapanlar görür)
insert into storage.buckets (id, name, public) values ('musteri-dosyalari','musteri-dosyalari', false)
on conflict (id) do update set public = false;
drop policy if exists "musteri dosya oku" on storage.objects;
create policy "musteri dosya oku" on storage.objects for select to authenticated using (bucket_id = 'musteri-dosyalari');
drop policy if exists "musteri dosya yukle" on storage.objects;
create policy "musteri dosya yukle" on storage.objects for insert to authenticated with check (bucket_id = 'musteri-dosyalari');
drop policy if exists "musteri dosya sil" on storage.objects;
create policy "musteri dosya sil" on storage.objects for delete to authenticated using (bucket_id = 'musteri-dosyalari');
