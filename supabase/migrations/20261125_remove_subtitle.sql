do $$
declare
  unresolved_items integer;
begin
  with legacy_features as (
    select
      item.id,
      count(*) filter (where btrim(feature) <> '') as feature_count,
      (
        (case when btrim(item.other_feature_1) = '' then 1 else 0 end) +
        (case when btrim(item.other_feature_2) = '' then 1 else 0 end) +
        (case when btrim(item.other_feature_3) = '' then 1 else 0 end)
      ) as available_slots
    from public.lost_items as item
    cross join lateral regexp_split_to_table(
      item.subtitle,
      '[、,，;；。.!！?？\n]+'
    ) as split(feature)
    where btrim(item.subtitle) <> ''
    group by
      item.id,
      item.other_feature_1,
      item.other_feature_2,
      item.other_feature_3
  )
  select count(*)
  into unresolved_items
  from legacy_features
  where feature_count > available_slots;

  if unresolved_items > 0 then
    raise exception
      'Cannot remove subtitle: % rows have more subtitle parts than empty other-feature slots. Move or remove the extra subtitle details, then rerun this migration.',
      unresolved_items;
  end if;
end;
$$;

with legacy as (
  select
    item.id,
    item.other_feature_1,
    item.other_feature_2,
    item.other_feature_3,
    array(
      select btrim(feature)
      from regexp_split_to_table(item.subtitle, '[、,，;；。.!！?？\n]+')
        with ordinality as split(feature, position)
      where btrim(feature) <> ''
      order by position
    ) as features
  from public.lost_items as item
  where btrim(item.subtitle) <> ''
),
available_slots as (
  select legacy.id, slot.number,
    row_number() over (partition by legacy.id order by slot.number) as position
  from legacy
  cross join lateral (values
    (1, nullif(btrim(legacy.other_feature_1), '')),
    (2, nullif(btrim(legacy.other_feature_2), '')),
    (3, nullif(btrim(legacy.other_feature_3), ''))
  ) as slot(number, current_value)
  where slot.current_value is null
),
subtitle_parts as (
  select legacy.id, feature.value,
    row_number() over (partition by legacy.id order by feature.position) as position
  from legacy
  cross join lateral unnest(legacy.features) with ordinality
    as feature(value, position)
),
assigned as (
  select available_slots.id, available_slots.number, subtitle_parts.value
  from available_slots
  join subtitle_parts using (id, position)
),
merged as (
  select
    legacy.id,
    coalesce(max(assigned.value) filter (where assigned.number = 1), legacy.other_feature_1) as other_feature_1,
    coalesce(max(assigned.value) filter (where assigned.number = 2), legacy.other_feature_2) as other_feature_2,
    coalesce(max(assigned.value) filter (where assigned.number = 3), legacy.other_feature_3) as other_feature_3
  from legacy
  left join assigned using (id)
  group by legacy.id, legacy.other_feature_1, legacy.other_feature_2, legacy.other_feature_3
)
update public.lost_items as item
set
  other_feature_1 = merged.other_feature_1,
  other_feature_2 = merged.other_feature_2,
  other_feature_3 = merged.other_feature_3
from merged
where item.id = merged.id;

update public.lost_items
set
  keywords = left(concat_ws(
    ' ',
    name,
    category,
    color,
    other_feature_1,
    other_feature_2,
    other_feature_3
  ), 1000),
  embedding = null;

alter table public.lost_items
  drop column if exists subtitle;
