-- Saved creative artifacts (free drawing, complete-the-drawing,
-- activity drawings). Immutable once created — no update policy, no
-- updated_at column. The composite foreign key guarantees child_id
-- and parent_id actually belong together (see children's
-- `unique (id, parent_id)`), not just that each is independently
-- valid.
create table public.drawings (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null,
  parent_id uuid not null,
  source text not null check (source in ('free_draw', 'complete_drawing', 'activity')),
  source_ref text,
  image_path text not null,
  thumbnail_path text,
  metadata jsonb,
  created_at timestamptz not null default now(),
  foreign key (child_id, parent_id) references public.children (id, parent_id) on delete cascade
);

comment on table public.drawings is
  'Saved creative artifacts. Immutable once created. (child_id, parent_id) is a composite FK into children(id, parent_id) so ownership is guaranteed at the database level, not just via RLS.';

create index drawings_parent_created_idx on public.drawings (parent_id, created_at desc);
create index drawings_child_id_idx on public.drawings (child_id);

alter table public.drawings enable row level security;

create policy "Parents can view their children's drawings"
  on public.drawings for select
  to authenticated
  using (parent_id = auth.uid());

create policy "Parents can add drawings for their own children"
  on public.drawings for insert
  to authenticated
  with check (
    parent_id = auth.uid()
    and exists (
      select 1 from public.children c
      where c.id = child_id and c.parent_id = auth.uid()
    )
  );

create policy "Parents can delete their children's drawings"
  on public.drawings for delete
  to authenticated
  using (parent_id = auth.uid());

-- No update policy: drawings are immutable once saved.
