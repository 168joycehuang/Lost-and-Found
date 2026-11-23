alter table public.lost_items
  add column if not exists subtitle text not null default '' check (char_length(subtitle) <= 240);
