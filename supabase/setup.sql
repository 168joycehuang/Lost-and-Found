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
  status text not null default 'pending' check (status in ('pending', 'claimed')),
  created_at timestamptz not null default now(),
  claimed_at timestamptz
);

alter table public.lost_items
  add column if not exists other_feature_1 text not null default '' check (char_length(other_feature_1) <= 500),
  add column if not exists other_feature_2 text not null default '' check (char_length(other_feature_2) <= 500),
  add column if not exists other_feature_3 text not null default '' check (char_length(other_feature_3) <= 500),
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
