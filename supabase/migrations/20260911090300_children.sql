-- Child profiles. Children never authenticate independently — every
-- child-mode action in the app runs under the parent's own session.
-- `unique (id, parent_id)` is the anchor that every downstream
-- composite foreign key (drawings, child_stories, ai_insights,
-- appointments) references to guarantee a child actually belongs to
-- the parent_id stored alongside it.
create table public.children (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  -- Robust, boundary-inclusive age-range check: LONOTQ targets children
  -- aged 4-10 inclusive. `birth_date <= current_date - 4 years` means
  -- "has already had their 4th birthday" (today counts); `birth_date >
  -- current_date - 11 years` means "has not yet had their 11th
  -- birthday" (turning 11 today is excluded). Re-evaluated on every
  -- UPDATE, not just INSERT — see migration-pass notes on the
  -- consequence of that.
  birth_date date not null check (
    birth_date <= current_date - interval '4 years'
    and birth_date > current_date - interval '11 years'
  ),
  avatar_color text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, parent_id)
);

comment on table public.children is
  'A child profile owned by a parent. No independent auth identity by design.';

create index children_parent_id_idx on public.children (parent_id);

alter table public.children enable row level security;

create trigger set_updated_at
  before update on public.children
  for each row execute function public.set_updated_at();

create policy "Parents can view their own children"
  on public.children for select
  to authenticated
  using (parent_id = auth.uid());

create policy "Parents can insert their own children"
  on public.children for insert
  to authenticated
  with check (parent_id = auth.uid());

create policy "Parents can update their own children"
  on public.children for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

create policy "Parents can delete their own children"
  on public.children for delete
  to authenticated
  using (parent_id = auth.uid());
