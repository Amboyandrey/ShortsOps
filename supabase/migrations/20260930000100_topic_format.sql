-- facts-shorts now makes two kinds of Shorts: single-fact stories and countdown rankings.
alter table public.topics
  add column format text not null default 'story' check (format in ('story', 'ranking')),
  add column rank_count smallint check (rank_count between 2 and 20),
  add column ranking_criterion text;
