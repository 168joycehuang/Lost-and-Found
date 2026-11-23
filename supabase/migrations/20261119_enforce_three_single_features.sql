with split_features as (
  select
    id,
    regexp_split_to_array(
      concat_ws(
        '、',
        nullif(btrim(other_feature_1), ''),
        nullif(btrim(other_feature_2), ''),
        nullif(btrim(other_feature_3), '')
      ),
      '\s*[、,，;；\n]+\s*'
    ) as parts
  from public.lost_items
)
update public.lost_items as item
set
  other_feature_1 = coalesce(nullif(btrim(split_features.parts[1]), ''), ''),
  other_feature_2 = coalesce(nullif(btrim(split_features.parts[2]), ''), ''),
  other_feature_3 = coalesce(nullif(btrim(split_features.parts[3]), ''), '')
from split_features
where item.id = split_features.id;

alter table public.lost_items
  drop constraint if exists lost_items_other_feature_1_single_item_check,
  drop constraint if exists lost_items_other_feature_2_single_item_check,
  drop constraint if exists lost_items_other_feature_3_single_item_check,
  add constraint lost_items_other_feature_1_single_item_check check (other_feature_1 !~ '[、,，;；\n]'),
  add constraint lost_items_other_feature_2_single_item_check check (other_feature_2 !~ '[、,，;；\n]'),
  add constraint lost_items_other_feature_3_single_item_check check (other_feature_3 !~ '[、,，;；\n]');
