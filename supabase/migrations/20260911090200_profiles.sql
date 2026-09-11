-- Parent accounts. Mirrors auth.users 1:1. `role = 'admin'` rows are
-- created only via a trusted service-role script, never by client
-- signup — enforced below by the update policy's WITH CHECK.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'parent' check (role in ('parent', 'admin')),
  full_name text not null,
  avatar_color text,
  locale text not null default 'ar' check (locale in ('en', 'ar')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per parent user. Admin rows are provisioned out-of-band by a service role, never via client signup or client UPDATE.';

alter table public.profiles enable row level security;

create trigger set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create policy "Parents can view their own profile"
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

create policy "Parents can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = 'parent');

-- No insert policy: rows are created by the handle_new_user trigger
-- (see the auth-signup-trigger migration) in a service-role context.
-- No delete policy: account deletion is a service-role/API-level flow,
-- not a raw client DELETE.
