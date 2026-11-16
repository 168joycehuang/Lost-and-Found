-- Run this script in the Supabase SQL Editor. Do not expose it as a website file.
create table if not exists public.lost_items (
  id text primary key,
  name text not null check (char_length(btrim(name)) between 1 and 200),
  category text not null default '其他' check (char_length(category) <= 80),
  color text not null default '' check (char_length(color) <= 100),
  material text not null default '' check (char_length(material) <= 150),
  features text not null default '' check (char_length(features) <= 500),
  keywords text not null check (char_length(keywords) <= 1000),
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
