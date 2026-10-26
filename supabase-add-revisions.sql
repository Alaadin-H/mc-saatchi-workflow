-- ============================================================================
-- EDITS / REVISIONS: a task can have many edits (round 1, round 2, ...)
-- Run once in Supabase > SQL Editor. Safe to run again.
-- Only adds a new table. It does not change tasks, app_settings or their policies.
-- ============================================================================

create table if not exists public.task_revisions (
  id             bigint generated always as identity primary key,
  task_id        text not null references public.tasks(task_id) on delete cascade on update cascade,
  revision_no    int  not null default 0,
  owner_note     text default '',   -- feedback / requested changes from the task owner
  delivery_link  text default '',   -- new delivery link after the edit
  delivery_note  text default '',   -- note from whoever delivered the edit
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (task_id, revision_no)
);

create index if not exists task_revisions_task_idx on public.task_revisions (task_id);

-- Numbering 1, 2, 3... per task, assigned by the database
create or replace function public.task_revisions_set_no()
returns trigger language plpgsql as $$
begin
  select coalesce(max(revision_no), 0) + 1 into new.revision_no
  from public.task_revisions where task_id = new.task_id;
  return new;
end $$;

drop trigger if exists trg_task_revisions_set_no on public.task_revisions;
create trigger trg_task_revisions_set_no
  before insert on public.task_revisions
  for each row execute function public.task_revisions_set_no();

create or replace function public.task_revisions_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_task_revisions_touch on public.task_revisions;
create trigger trg_task_revisions_touch
  before update on public.task_revisions
  for each row execute function public.task_revisions_touch();

-- Same access model as the tasks table (the site has no login)
alter table public.task_revisions enable row level security;

drop policy if exists "Allow public read revisions"   on public.task_revisions;
drop policy if exists "Allow public insert revisions" on public.task_revisions;
drop policy if exists "Allow public update revisions" on public.task_revisions;
drop policy if exists "Allow public delete revisions" on public.task_revisions;
create policy "Allow public read revisions"   on public.task_revisions for select using (true);
create policy "Allow public insert revisions" on public.task_revisions for insert with check (true);
create policy "Allow public update revisions" on public.task_revisions for update using (true);
create policy "Allow public delete revisions" on public.task_revisions for delete using (true);

-- Live updates
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'task_revisions'
  ) then
    alter publication supabase_realtime add table public.task_revisions;
  end if;
end $$;
