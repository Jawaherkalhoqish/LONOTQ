-- A booking between one specific child and one specialist. Composite
-- FK guarantees child/parent ownership at the database level. Status
-- transitions to confirmed/completed are service-role only; a parent
-- may only cancel — enforced below by a dedicated trigger, since RLS
-- alone cannot express "only this specific value transition is
-- allowed."
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null,
  parent_id uuid not null,
  specialist_id uuid not null references public.specialists (id) on delete restrict,
  scheduled_at timestamptz not null,
  status text not null default 'requested' check (
    status in ('requested', 'confirmed', 'completed', 'cancelled')
  ),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (child_id, parent_id) references public.children (id, parent_id) on delete cascade,
  check (scheduled_at > created_at)
);

comment on table public.appointments is
  'A booking between one child and one specialist. Parents may only cancel; confirm/complete transitions require the service role.';

create index appointments_parent_scheduled_idx on public.appointments (parent_id, scheduled_at);
create index appointments_child_id_idx on public.appointments (child_id);
create index appointments_specialist_id_idx on public.appointments (specialist_id);

-- Prevents double-booking the same specialist at the same instant.
-- Partial (status in requested/confirmed only) so a cancelled or
-- completed appointment never blocks that slot from being rebooked,
-- and full appointment history is preserved either way.
create unique index appointments_specialist_slot_uidx
  on public.appointments (specialist_id, scheduled_at)
  where status in ('requested', 'confirmed');

alter table public.appointments enable row level security;

create trigger set_updated_at
  before update on public.appointments
  for each row execute function public.set_updated_at();

create policy "Parents can view their own appointments"
  on public.appointments for select
  to authenticated
  using (parent_id = auth.uid());

create policy "Parents can request appointments for their own children"
  on public.appointments for insert
  to authenticated
  with check (
    parent_id = auth.uid()
    and status = 'requested'
    and exists (
      select 1 from public.children c
      where c.id = child_id and c.parent_id = auth.uid()
    )
  );

create policy "Parents can update their own appointments"
  on public.appointments for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

-- No delete policy: cancellation is a status change, not a row
-- deletion — appointment history is preserved.

-- Enforces WHAT a parent-initiated update may actually change: only
-- `status`, and only requested/confirmed -> cancelled. Two trusted
-- execution contexts bypass this check entirely:
--
--   1. auth.role() = 'service_role' — a request made through
--      Supabase's API layer (PostgREST) using the service-role key,
--      e.g. a background job or a future admin/specialist-portal
--      server route. This is the normal, intended path for staff
--      operations once one exists.
--
--   2. current_setting('is_superuser', true) = 'on' — a direct
--      superuser session, which is what the Supabase Studio SQL
--      editor and a plain `psql` connection as `postgres` both use
--      (and what applies this very migration). auth.role() is NOT
--      set in that context, because there is no PostgREST-issued JWT
--      — that gap is exactly the audit finding this fixes: without
--      this second condition, staff using Studio to confirm or
--      complete an appointment today (the only way to do so, since
--      no admin UI exists yet) would be incorrectly blocked by the
--      very restriction meant only for ordinary parent sessions.
--      `is_superuser` is a standard Postgres session parameter built
--      for exactly this check, so no role name needs to be
--      hardcoded.
--
-- Neither condition is reachable from the Flutter client: it only
-- ever connects as the `authenticated` role, holds no superuser
-- privilege, and never has access to the service-role secret key.
-- Ordinary parent sessions are therefore restricted exactly as
-- before — this is a bug fix for a legitimate operational gap, not a
-- new bypass.
create or replace function public.enforce_appointment_status_transition()
returns trigger
language plpgsql
as $$
begin
  if auth.role() = 'service_role'
     or current_setting('is_superuser', true) = 'on' then
    return new;
  end if;

  if new.status is distinct from old.status then
    if not (old.status in ('requested', 'confirmed') and new.status = 'cancelled') then
      raise exception 'Parents may only cancel a requested or confirmed appointment.';
    end if;
  end if;

  if new.child_id is distinct from old.child_id
     or new.parent_id is distinct from old.parent_id
     or new.specialist_id is distinct from old.specialist_id
     or new.scheduled_at is distinct from old.scheduled_at
     or new.notes is distinct from old.notes then
    raise exception 'Parents may only change an appointment''s status to cancelled.';
  end if;

  return new;
end;
$$;

create trigger enforce_appointment_status_transition
  before update on public.appointments
  for each row execute function public.enforce_appointment_status_transition();
