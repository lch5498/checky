alter table public.anniversaries
  add column if not exists custom_category_label text;

alter table public.anniversaries
  drop constraint if exists anniversaries_custom_category_label_check;

alter table public.anniversaries
  add constraint anniversaries_custom_category_label_check
    check (
      custom_category_label is null
      or char_length(btrim(custom_category_label)) between 1 and 40
    );
