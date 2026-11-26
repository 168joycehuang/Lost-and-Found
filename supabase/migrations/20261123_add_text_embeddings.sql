create extension if not exists vector with schema extensions;

alter table public.lost_items
  add column if not exists embedding extensions.vector(1536);

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
