-- Cautious, pattern-based observations only — never a diagnosis.
-- There is deliberately no emotion/diagnosis/severity column: the
-- schema can only ever represent a category + a cautious text
-- observation + an optional confidence score. Writable only by a
-- trusted service role (the future AI pipeline) — never the client.
create table public.ai_insights (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null,
  parent_id uuid not null,
  category text not null check (
    category in (
      'color_usage', 'shape_usage', 'composition',
      'repeated_elements', 'activity_behavior', 'changes_over_time'
    )
  ),
  observation text not null check (length(trim(observation)) > 0),
  confidence numeric(3,2) check (confidence between 0 and 1),
  source_drawing_ids uuid[],
  generated_at timestamptz not null default now(),
  is_visible_to_parent boolean not null default true,
  foreign key (child_id, parent_id) references public.children (id, parent_id) on delete cascade
);

comment on table public.ai_insights is
  'Cautious, pattern-based observations only — never a diagnosis. No client insert/update/delete policy exists; written only by a trusted service role.';

create index ai_insights_parent_generated_idx on public.ai_insights (parent_id, generated_at desc);
create index ai_insights_child_id_idx on public.ai_insights (child_id);

alter table public.ai_insights enable row level security;

create policy "Parents can view visible insights for their children"
  on public.ai_insights for select
  to authenticated
  using (parent_id = auth.uid() and is_visible_to_parent = true);

-- Deliberately no insert/update/delete policy for the authenticated role.
