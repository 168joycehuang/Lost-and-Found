alter table public.lost_items
  add column if not exists other_feature_1 text not null default '' check (char_length(other_feature_1) <= 500),
  add column if not exists other_feature_2 text not null default '' check (char_length(other_feature_2) <= 500),
  add column if not exists other_feature_3 text not null default '' check (char_length(other_feature_3) <= 500);

with legacy_features as (
  select
    id,
    regexp_split_to_array(btrim(features), '\s*[、,，;；\n]+\s*') as parts
  from public.lost_items
  where btrim(features) <> ''
)
update public.lost_items as item
set
  other_feature_1 = coalesce(nullif(btrim(legacy_features.parts[1]), ''), ''),
  other_feature_2 = coalesce(nullif(btrim(legacy_features.parts[2]), ''), ''),
  other_feature_3 = coalesce(nullif(btrim(array_to_string(legacy_features.parts[3:], '、')), ''), '')
from legacy_features
where item.id = legacy_features.id
  and item.other_feature_1 = ''
  and item.other_feature_2 = ''
  and item.other_feature_3 = '';
