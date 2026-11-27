-- Run this script in the Supabase SQL Editor. Do not expose it as a website file.
create extension if not exists vector with schema extensions;

create table if not exists public.lost_items (
  id text primary key,
  name text not null check (char_length(btrim(name)) between 1 and 200),
  category text not null default '其他' check (char_length(category) <= 80),
  color text not null default '' check (char_length(color) <= 100),
  material text not null default '' check (char_length(material) <= 150),
  features text not null default '' check (char_length(features) <= 500),
  other_feature_1 text not null default '' check (char_length(other_feature_1) <= 500),
  other_feature_2 text not null default '' check (char_length(other_feature_2) <= 500),
  other_feature_3 text not null default '' check (char_length(other_feature_3) <= 500),
  keywords text not null check (char_length(keywords) <= 1000),
  embedding extensions.vector(1536),
  location text not null check (char_length(btrim(location)) between 1 and 200),
  found_at date not null default (now() at time zone 'Asia/Taipei')::date,
  pickup_location text not null check (char_length(btrim(pickup_location)) between 1 and 200),
  contact text not null default '' check (char_length(contact) <= 200),
  photos jsonb not null check (
    jsonb_typeof(photos) = 'array'
    and jsonb_array_length(photos) between 1 and 3
  ),
  edit_token_hash text,
  status text not null default 'pending' check (status in ('pending', 'claimed')),
  created_at timestamptz not null default now(),
  claimed_at timestamptz
);

alter table public.lost_items
  add column if not exists other_feature_1 text not null default '' check (char_length(other_feature_1) <= 500),
  add column if not exists other_feature_2 text not null default '' check (char_length(other_feature_2) <= 500),
  add column if not exists other_feature_3 text not null default '' check (char_length(other_feature_3) <= 500),
  add column if not exists edit_token_hash text,
  add column if not exists embedding extensions.vector(1536);

alter table public.lost_items
  drop constraint if exists lost_items_other_feature_1_single_item_check,
  drop constraint if exists lost_items_other_feature_2_single_item_check,
  drop constraint if exists lost_items_other_feature_3_single_item_check,
  add constraint lost_items_other_feature_1_single_item_check check (other_feature_1 !~ '[、,，;；\n]'),
  add constraint lost_items_other_feature_2_single_item_check check (other_feature_2 !~ '[、,，;；\n]'),
  add constraint lost_items_other_feature_3_single_item_check check (other_feature_3 !~ '[、,，;；\n]');

create index if not exists lost_items_pending_found_at_idx
  on public.lost_items (found_at desc)
  where status = 'pending';

alter table public.lost_items enable row level security;
grant usage on schema public to anon;
grant select, insert on public.lost_items to anon;
revoke update, delete, truncate on public.lost_items from public, anon, authenticated;

drop policy if exists "Anyone can view pending lost items" on public.lost_items;
create policy "Anyone can view pending lost items"
  on public.lost_items for select to anon
  using (status = 'pending');

drop policy if exists "Anyone can report pending lost items" on public.lost_items;
create policy "Anyone can report pending lost items"
  on public.lost_items for insert to anon
  with check (status = 'pending' and claimed_at is null);

create or replace function public.claim_lost_item(p_item_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  did_claim boolean;
begin
  update public.lost_items
  set status = 'claimed', claimed_at = now()
  where id = p_item_id and status = 'pending'
  returning true into did_claim;

  return coalesce(did_claim, false);
end;
$$;

revoke all on function public.claim_lost_item(text) from public, anon, authenticated;
grant execute on function public.claim_lost_item(text) to anon;

grant usage on schema extensions to anon;

create or replace function public.match_lost_items(
  query_embedding extensions.vector(1536),
  search_text text,
  search_location text default null,
  search_from date default null,
  max_results integer default 50
)
returns table(
  item jsonb,
  similarity double precision,
  exact_title boolean,
  literal_match boolean
)
language sql
stable
as $$
  with normalized_query as (
    select lower(regexp_replace(btrim(search_text), '[[:space:]]', '', 'g')) as text
  ),
  candidates as (
    select
      lost_item,
      case
        when lost_item.embedding is null then null::double precision
        else (1 - (lost_item.embedding <=> query_embedding))::double precision
      end as similarity,
      lower(regexp_replace(btrim(lost_item.name), '[[:space:]]', '', 'g')) =
        normalized_query.text as exact_title,
      position(normalized_query.text in fields.searchable_text) > 0 as literal_match,
      lost_item.embedding <=> query_embedding as distance,
      lost_item.found_at
    from public.lost_items as lost_item
    cross join normalized_query
    cross join lateral (
      select lower(regexp_replace(concat_ws(
        ' ',
        lost_item.name,
        lost_item.category,
        lost_item.color,
        lost_item.other_feature_1,
        lost_item.other_feature_2,
        lost_item.other_feature_3
      ), '[[:space:]]', '', 'g')) as searchable_text
    ) as fields
    where lost_item.status = 'pending'
      and normalized_query.text <> ''
      and (search_location is null
        or position(lower(lost_item.location) in lower(search_location)) > 0
        or position(lower(search_location) in lower(lost_item.location)) > 0)
      and (search_from is null or lost_item.found_at >= search_from)
  )
  select
    to_jsonb(candidates.lost_item) - 'embedding',
    candidates.similarity,
    candidates.exact_title,
    candidates.literal_match
  from candidates
  where candidates.distance is not null or candidates.literal_match
  order by
    candidates.exact_title desc,
    candidates.literal_match desc,
    candidates.distance asc nulls last,
    candidates.found_at desc
  limit least(greatest(coalesce(max_results, 50), 1), 100);
$$;

revoke all on function public.match_lost_items(
  extensions.vector, text, text, date, integer
) from public, authenticated;
grant execute on function public.match_lost_items(
  extensions.vector, text, text, date, integer
) to anon;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'lost-items',
  'lost-items',
  true,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

grant insert, select on storage.objects to anon;

drop policy if exists "Anyone can upload PineFinder photos" on storage.objects;
create policy "Anyone can upload PineFinder photos"
  on storage.objects for insert to anon
  with check (bucket_id = 'lost-items');

drop policy if exists "Anyone can read PineFinder photos" on storage.objects;
create policy "Anyone can read PineFinder photos"
  on storage.objects for select to anon
  using (bucket_id = 'lost-items');

create table if not exists public.lost_item_edit_keys (
  item_id text primary key references public.lost_items(id) on delete cascade,
  token_hash text not null,
  created_at timestamptz not null default now()
);

alter table public.lost_item_edit_keys enable row level security;
revoke all on public.lost_item_edit_keys from public, anon, authenticated;

create or replace function public.store_lost_item_edit_key()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.edit_token_hash is not null then
    insert into public.lost_item_edit_keys (item_id, token_hash)
    values (new.id, new.edit_token_hash);

    update public.lost_items
    set edit_token_hash = null
    where id = new.id;
  end if;

  return new;
end;
$$;

revoke all on function public.store_lost_item_edit_key() from public, anon, authenticated;

drop trigger if exists store_lost_item_edit_key on public.lost_items;
create trigger store_lost_item_edit_key
after insert on public.lost_items
for each row execute function public.store_lost_item_edit_key();

create or replace function public.get_my_lost_items(p_items jsonb)
returns table(payload jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception '上傳紀錄格式錯誤';
  end if;

  if jsonb_array_length(p_items) > 500 then
    raise exception '單次最多載入 500 筆上傳紀錄';
  end if;

  return query
  select to_jsonb(item) - 'embedding' - 'edit_token_hash' as payload
  from jsonb_to_recordset(p_items) as requested(id text, edit_token text)
  join public.lost_item_edit_keys as edit_key
    on edit_key.item_id = requested.id
   and edit_key.token_hash = pg_catalog.encode(
     pg_catalog.sha256(pg_catalog.convert_to(requested.edit_token, 'UTF8')),
     'hex'
   )
  join public.lost_items as item on item.id = requested.id
  where length(requested.id) <= 40
    and length(requested.edit_token) between 40 and 100
  order by item.found_at desc, item.created_at desc;
end;
$$;

revoke all on function public.get_my_lost_items(jsonb) from public, anon, authenticated;
grant execute on function public.get_my_lost_items(jsonb) to anon;

create or replace function public.edit_lost_item(
  p_item_id text,
  p_edit_token text,
  p_item jsonb,
  p_embedding extensions.vector(1536)
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_item jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) is distinct from 'object' or p_embedding is null then
    raise exception '更新資料不完整，請重新整理後再試';
  end if;

  if p_edit_token is null or length(p_edit_token) not between 40 and 100 then
    raise exception '管理憑證無效，請從此瀏覽器的「我的上傳」重新操作'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.lost_item_edit_keys as edit_key
    where edit_key.item_id = p_item_id
      and edit_key.token_hash = pg_catalog.encode(
        pg_catalog.sha256(pg_catalog.convert_to(p_edit_token, 'UTF8')),
        'hex'
      )
  ) then
    raise exception '找不到此筆資料的有效管理憑證'
      using errcode = '42501';
  end if;

  update public.lost_items as item
  set
    name = btrim(coalesce(p_item->>'name', '')),
    category = coalesce(nullif(btrim(p_item->>'category'), ''), '其他'),
    color = btrim(coalesce(p_item->>'color', '')),
    other_feature_1 = btrim(coalesce(p_item->>'other_feature_1', '')),
    other_feature_2 = btrim(coalesce(p_item->>'other_feature_2', '')),
    other_feature_3 = btrim(coalesce(p_item->>'other_feature_3', '')),
    keywords = coalesce(p_item->>'keywords', ''),
    location = btrim(coalesce(p_item->>'location', '')),
    found_at = (p_item->>'found_at')::date,
    pickup_location = btrim(coalesce(p_item->>'pickup_location', '')),
    contact = btrim(coalesce(p_item->>'contact', '')),
    embedding = p_embedding
  where item.id = p_item_id
    and item.status = 'pending'
  returning to_jsonb(item) - 'embedding' - 'edit_token_hash'
  into updated_item;

  if updated_item is null then
    raise exception '此物品已領取或不存在，無法編輯'
      using errcode = 'P0002';
  end if;

  return updated_item;
end;
$$;

revoke all on function public.edit_lost_item(
  text, text, jsonb, extensions.vector
) from public, anon, authenticated;
grant execute on function public.edit_lost_item(
  text, text, jsonb, extensions.vector
) to anon;

notify pgrst, 'reload schema';
