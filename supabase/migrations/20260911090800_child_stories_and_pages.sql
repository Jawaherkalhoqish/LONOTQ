-- A story a specific child generated via the My Story wizard.
-- Immutable once created. Composite FK guarantees child/parent
-- ownership at the database level (same technique as drawings).
create table public.child_stories (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null,
  parent_id uuid not null,
  mode text not null check (mode in ('imagination', 'my_day', 'complete')),
  hero text not null,
  companion text not null,
  story_type text not null,
  situation text not null,
  title text not null,
  cover_color text not null,
  created_at timestamptz not null default now(),
  foreign key (child_id, parent_id) references public.children (id, parent_id) on delete cascade
);

comment on table public.child_stories is
  'A story a specific child generated via the My Story wizard. Immutable once created.';

create index child_stories_parent_created_idx on public.child_stories (parent_id, created_at desc);
create index child_stories_child_id_idx on public.child_stories (child_id);

alter table public.child_stories enable row level security;

create policy "Parents can view their children's stories"
  on public.child_stories for select
  to authenticated
  using (parent_id = auth.uid());

create policy "Parents can add stories for their own children"
  on public.child_stories for insert
  to authenticated
  with check (
    parent_id = auth.uid()
    and exists (
      select 1 from public.children c
      where c.id = child_id and c.parent_id = auth.uid()
    )
  );

create policy "Parents can delete their children's stories"
  on public.child_stories for delete
  to authenticated
  using (parent_id = auth.uid());

-- Ordered pages of a child-generated story. No parent_id here:
-- ownership is already fully guaranteed transitively through
-- child_stories' own composite FK, so duplicating it down another
-- level would be redundant, not extra-safe.
create table public.child_story_pages (
  id uuid primary key default gen_random_uuid(),
  child_story_id uuid not null references public.child_stories (id) on delete cascade,
  page_index int not null,
  text text not null,
  character_mood text not null,
  created_at timestamptz not null default now(),
  unique (child_story_id, page_index)
);

comment on table public.child_story_pages is
  'Ordered pages of a child-generated story. Ownership inherited from child_stories.';

alter table public.child_story_pages enable row level security;

create policy "Parents can view their children's story pages"
  on public.child_story_pages for select
  to authenticated
  using (
    exists (
      select 1 from public.child_stories cs
      where cs.id = child_story_id and cs.parent_id = auth.uid()
    )
  );

create policy "Parents can add pages to their children's stories"
  on public.child_story_pages for insert
  to authenticated
  with check (
    exists (
      select 1 from public.child_stories cs
      where cs.id = child_story_id and cs.parent_id = auth.uid()
    )
  );

create policy "Parents can delete their children's story pages"
  on public.child_story_pages for delete
  to authenticated
  using (
    exists (
      select 1 from public.child_stories cs
      where cs.id = child_story_id and cs.parent_id = auth.uid()
    )
  );
