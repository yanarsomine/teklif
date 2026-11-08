-- 4) Teklif PDF arşivi (gizli kova; sadece giriş yapmış kullanıcılar okur/yazar — gün sonu yedeği buradan alınır)
insert into storage.buckets (id, name, public) values ('teklifler','teklifler', false)
on conflict (id) do update set public = false;
drop policy if exists "teklif pdf oku" on storage.objects;
create policy "teklif pdf oku" on storage.objects for select to authenticated using (bucket_id = 'teklifler');
drop policy if exists "teklif pdf yukle" on storage.objects;
create policy "teklif pdf yukle" on storage.objects for insert to authenticated with check (bucket_id = 'teklifler');
drop policy if exists "teklif pdf guncelle" on storage.objects;
create policy "teklif pdf guncelle" on storage.objects for update to authenticated using (bucket_id = 'teklifler') with check (bucket_id = 'teklifler');
