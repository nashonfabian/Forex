-- MY MARKET LAB: Supabase schema. Run once in Supabase > SQL Editor (safe to read first; it only creates objects).
-- Generated together with the app's local schema so both sides always match.

create or replace function public.set_server_updated_at() returns trigger language plpgsql as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end
$$;

create table if not exists public.study_plans (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  title text NOT NULL,
  description text,
  start_date text,
  length_days integer NOT NULL DEFAULT 90,
  status text NOT NULL DEFAULT 'active'
);
create index if not exists idx_study_plans_cursor on public.study_plans (owner_id, server_updated_at, id);
alter table public.study_plans enable row level security;
drop policy if exists own_rows on public.study_plans;
create policy own_rows on public.study_plans for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_study_plans_server_ts on public.study_plans;
create trigger trg_study_plans_server_ts before insert or update on public.study_plans for each row execute function public.set_server_updated_at();

create table if not exists public.lessons (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  plan_id text NOT NULL REFERENCES study_plans(id) DEFERRABLE INITIALLY DEFERRED,
  phase_no integer,
  phase_title text,
  week_no integer,
  day_no integer,
  order_index integer NOT NULL DEFAULT 0,
  title text NOT NULL,
  objective text,
  assignment text,
  is_milestone integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'not_started',
  scheduled_date text,
  completed_at text
);
create index if not exists idx_lessons_cursor on public.lessons (owner_id, server_updated_at, id);
alter table public.lessons enable row level security;
drop policy if exists own_rows on public.lessons;
create policy own_rows on public.lessons for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_lessons_server_ts on public.lessons;
create trigger trg_lessons_server_ts before insert or update on public.lessons for each row execute function public.set_server_updated_at();

create table if not exists public.daily_tasks (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  plan_date text NOT NULL,
  title text NOT NULL,
  kind text NOT NULL DEFAULT 'custom',
  lesson_id text REFERENCES lessons(id) DEFERRABLE INITIALLY DEFERRED,
  status text NOT NULL DEFAULT 'todo',
  order_index integer NOT NULL DEFAULT 0
);
create index if not exists idx_daily_tasks_cursor on public.daily_tasks (owner_id, server_updated_at, id);
alter table public.daily_tasks enable row level security;
drop policy if exists own_rows on public.daily_tasks;
create policy own_rows on public.daily_tasks for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_daily_tasks_server_ts on public.daily_tasks;
create trigger trg_daily_tasks_server_ts before insert or update on public.daily_tasks for each row execute function public.set_server_updated_at();

create table if not exists public.notes (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  kind text NOT NULL DEFAULT 'note',
  title text,
  body_md text NOT NULL DEFAULT '',
  lesson_id text REFERENCES lessons(id) DEFERRABLE INITIALLY DEFERRED,
  book text,
  chapter text,
  page text,
  is_bookmarked integer NOT NULL DEFAULT 0,
  question_status text
);
create index if not exists idx_notes_cursor on public.notes (owner_id, server_updated_at, id);
alter table public.notes enable row level security;
drop policy if exists own_rows on public.notes;
create policy own_rows on public.notes for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_notes_server_ts on public.notes;
create trigger trg_notes_server_ts before insert or update on public.notes for each row execute function public.set_server_updated_at();

create table if not exists public.study_sessions (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  lesson_id text REFERENCES lessons(id) DEFERRABLE INITIALLY DEFERRED,
  started_at text NOT NULL,
  minutes integer NOT NULL DEFAULT 0,
  focus text
);
create index if not exists idx_study_sessions_cursor on public.study_sessions (owner_id, server_updated_at, id);
alter table public.study_sessions enable row level security;
drop policy if exists own_rows on public.study_sessions;
create policy own_rows on public.study_sessions for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_study_sessions_server_ts on public.study_sessions;
create trigger trg_study_sessions_server_ts before insert or update on public.study_sessions for each row execute function public.set_server_updated_at();

create table if not exists public.research_cases (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  title text NOT NULL,
  instrument text,
  timeframe text,
  observed_at text,
  market_condition text,
  reference_level text,
  exploration_direction text,
  status text NOT NULL DEFAULT 'draft',
  hypothesis text,
  evidence_for text,
  evidence_against text,
  acceptance_rejection text,
  alternatives text,
  invalidation text,
  confidence integer,
  hypothesis_locked_at text,
  outcome text,
  outcome_at text,
  outcome_summary text,
  final_lessons text,
  hypothesis_verdict text
);
create index if not exists idx_research_cases_cursor on public.research_cases (owner_id, server_updated_at, id);
alter table public.research_cases enable row level security;
drop policy if exists own_rows on public.research_cases;
create policy own_rows on public.research_cases for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_research_cases_server_ts on public.research_cases;
create trigger trg_research_cases_server_ts before insert or update on public.research_cases for each row execute function public.set_server_updated_at();

create table if not exists public.trades (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  case_id text REFERENCES research_cases(id) DEFERRABLE INITIALLY DEFERRED,
  account_type text NOT NULL DEFAULT 'demo',
  instrument text NOT NULL,
  direction text NOT NULL,
  opened_at text,
  closed_at text,
  entry_price double precision,
  exit_price double precision,
  stop_price double precision,
  target_price double precision,
  size double precision,
  initial_risk_minor integer,
  gross_pnl_minor integer,
  costs_minor integer NOT NULL DEFAULT 0,
  setup_rationale text,
  rule_adherence text,
  rule_notes text,
  process_notes text,
  review_text text,
  status text NOT NULL DEFAULT 'open'
);
create index if not exists idx_trades_cursor on public.trades (owner_id, server_updated_at, id);
alter table public.trades enable row level security;
drop policy if exists own_rows on public.trades;
create policy own_rows on public.trades for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_trades_server_ts on public.trades;
create trigger trg_trades_server_ts before insert or update on public.trades for each row execute function public.set_server_updated_at();

create table if not exists public.images (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  case_id text REFERENCES research_cases(id) DEFERRABLE INITIALLY DEFERRED,
  trade_id text REFERENCES trades(id) DEFERRABLE INITIALLY DEFERRED,
  phase text,
  caption text,
  observation text,
  instrument text,
  timeframe text,
  captured_at text,
  mime text,
  width integer,
  height integer,
  bytes bigint,
  sha256 text,
  storage_path text,
  uploaded_at text,
  sort_order integer NOT NULL DEFAULT 0
);
create index if not exists idx_images_cursor on public.images (owner_id, server_updated_at, id);
alter table public.images enable row level security;
drop policy if exists own_rows on public.images;
create policy own_rows on public.images for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_images_server_ts on public.images;
create trigger trg_images_server_ts before insert or update on public.images for each row execute function public.set_server_updated_at();

create table if not exists public.case_entries (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  case_id text NOT NULL REFERENCES research_cases(id) DEFERRABLE INITIALLY DEFERRED,
  phase text NOT NULL DEFAULT 'during',
  kind text NOT NULL DEFAULT 'observation',
  body text NOT NULL,
  image_id text REFERENCES images(id) DEFERRABLE INITIALLY DEFERRED
);
create index if not exists idx_case_entries_cursor on public.case_entries (owner_id, server_updated_at, id);
alter table public.case_entries enable row level security;
drop policy if exists own_rows on public.case_entries;
create policy own_rows on public.case_entries for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_case_entries_server_ts on public.case_entries;
create trigger trg_case_entries_server_ts before insert or update on public.case_entries for each row execute function public.set_server_updated_at();

create table if not exists public.reviews (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  kind text NOT NULL,
  period_start text NOT NULL,
  period_end text NOT NULL,
  answers_json text NOT NULL DEFAULT '{}',
  next_actions text,
  stats_snapshot_json text
);
create index if not exists idx_reviews_cursor on public.reviews (owner_id, server_updated_at, id);
alter table public.reviews enable row level security;
drop policy if exists own_rows on public.reviews;
create policy own_rows on public.reviews for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_reviews_server_ts on public.reviews;
create trigger trg_reviews_server_ts before insert or update on public.reviews for each row execute function public.set_server_updated_at();

create table if not exists public.tags (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  name text NOT NULL
);
create index if not exists idx_tags_cursor on public.tags (owner_id, server_updated_at, id);
alter table public.tags enable row level security;
drop policy if exists own_rows on public.tags;
create policy own_rows on public.tags for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_tags_server_ts on public.tags;
create trigger trg_tags_server_ts before insert or update on public.tags for each row execute function public.set_server_updated_at();

create table if not exists public.entity_tags (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  tag_id text NOT NULL REFERENCES tags(id) DEFERRABLE INITIALLY DEFERRED,
  entity_type text NOT NULL,
  entity_id text NOT NULL
);
create index if not exists idx_entity_tags_cursor on public.entity_tags (owner_id, server_updated_at, id);
alter table public.entity_tags enable row level security;
drop policy if exists own_rows on public.entity_tags;
create policy own_rows on public.entity_tags for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_entity_tags_server_ts on public.entity_tags;
create trigger trg_entity_tags_server_ts before insert or update on public.entity_tags for each row execute function public.set_server_updated_at();

create table if not exists public.links (
  id text primary key,
  owner_id uuid not null default auth.uid(),
  created_at text NOT NULL,
  updated_at text NOT NULL,
  deleted_at text,
  server_updated_at timestamptz not null default clock_timestamp(),
  from_type text NOT NULL,
  from_id text NOT NULL,
  to_type text NOT NULL,
  to_id text NOT NULL
);
create index if not exists idx_links_cursor on public.links (owner_id, server_updated_at, id);
alter table public.links enable row level security;
drop policy if exists own_rows on public.links;
create policy own_rows on public.links for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop trigger if exists trg_links_server_ts on public.links;
create trigger trg_links_server_ts before insert or update on public.links for each row execute function public.set_server_updated_at();

-- Evidence protection, enforced on the server as well as on the phone.
create or replace function public.guard_research_case() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.hypothesis_locked_at is not null and (
    new.hypothesis is distinct from old.hypothesis
    or new.evidence_for is distinct from old.evidence_for
    or new.evidence_against is distinct from old.evidence_against
    or new.acceptance_rejection is distinct from old.acceptance_rejection
    or new.alternatives is distinct from old.alternatives
    or new.invalidation is distinct from old.invalidation
    or new.confidence is distinct from old.confidence
    or new.hypothesis_locked_at is distinct from old.hypothesis_locked_at) then
    raise exception 'hypothesis_locked';
  end if;
  if tg_op = 'UPDATE' and old.hypothesis_locked_at is null and new.hypothesis_locked_at is not null
     and (new.hypothesis is null or length(trim(new.hypothesis)) = 0) then
    raise exception 'hypothesis_required';
  end if;
  if new.outcome is not null and new.hypothesis_locked_at is null then
    raise exception 'outcome_requires_locked_hypothesis';
  end if;
  return new;
end
$$;
drop trigger if exists trg_research_cases_guard on public.research_cases;
create trigger trg_research_cases_guard before insert or update on public.research_cases for each row execute function public.guard_research_case();

-- Private bucket for chart screenshots (10 MB per file). Each user can only touch their own folder: <user id>/<image id>.<ext>
insert into storage.buckets (id, name, public, file_size_limit)
values ('case-images', 'case-images', false, 10485760)
on conflict (id) do nothing;

drop policy if exists "case-images read own" on storage.objects;
drop policy if exists "case-images insert own" on storage.objects;
drop policy if exists "case-images update own" on storage.objects;
drop policy if exists "case-images delete own" on storage.objects;
create policy "case-images read own" on storage.objects for select to authenticated
  using (bucket_id = 'case-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "case-images insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'case-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "case-images update own" on storage.objects for update to authenticated
  using (bucket_id = 'case-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'case-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "case-images delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'case-images' and (storage.foldername(name))[1] = auth.uid()::text);
