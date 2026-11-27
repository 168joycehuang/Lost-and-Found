alter table public.lost_items
  add column if not exists edit_token_hash text;

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
