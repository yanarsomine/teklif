-- 7) Otomatik döviz kuru (TCMB döviz satış) — Supabase kendi içinde çeker, gizli anahtar gerekmez
-- Hafta içi İstanbul saatiyle 09:45 ve 15:45'te counter/rate kaydını günceller.
create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

create or replace function public.tcmb_kur_guncelle() returns text
language plpgsql security definer set search_path = public, extensions as $$
declare body text; x xml; t text; eur numeric; usd numeric; d date;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '25000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '15000');
  select content into body from extensions.http((
    'GET', 'https://www.tcmb.gov.tr/kurlar/today.xml',
    array[extensions.http_header('User-Agent', 'Mozilla/5.0')], null, null)::extensions.http_request);
  body := regexp_replace(body, '^\s*<\?xml[^>]*\?>', '');
  x := body::xml;
  t   := (xpath('/Tarih_Date/@Tarih', x))[1]::text;
  eur := ((xpath('/Tarih_Date/Currency[@CurrencyCode="EUR"]/ForexSelling/text()', x))[1]::text)::numeric;
  usd := ((xpath('/Tarih_Date/Currency[@CurrencyCode="USD"]/ForexSelling/text()', x))[1]::text)::numeric;
  d := to_date(t, 'DD.MM.YYYY');
  if d is null or usd is null or eur is null or usd < 10 or usd > 500 or eur <= usd or eur > 500 then
    raise exception 'TCMB değerleri beklenmedik: tarih % eur % usd %', t, eur, usd;
  end if;
  insert into public.docs(collection, id, data) values ('counter', 'rate', jsonb_build_object(
    'eur', eur, 'usd', usd, 'date', to_char(d, 'YYYY-MM-DD'), 'source', 'TCMB döviz satış',
    'fetchedAt', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))
  on conflict (collection, id) do update set data = excluded.data;
  return to_char(d, 'YYYY-MM-DD') || ' · EUR ' || eur || ' · USD ' || usd;
end; $$;
revoke all on function public.tcmb_kur_guncelle() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'tcmb-kur';
select cron.schedule('tcmb-kur', '45 6,12 * * 1-5', $$select public.tcmb_kur_guncelle()$$);  -- UTC = İstanbul 09:45, 15:45

-- Hemen bir kez çalıştır (sonuç satırında güncel kur görünür)
select public.tcmb_kur_guncelle() as guncel_kur;
