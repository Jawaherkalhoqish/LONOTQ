-- Current billing STATE per parent — never a payment processor.
-- No insert/update/delete policy exists for the authenticated role:
-- rows are created by handle_new_user (service-role context) and
-- changed only by a trusted service role/billing webhook.
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null unique references public.profiles (id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'premium')),
  billing_cycle text check (billing_cycle in ('monthly', 'annual')),
  status text not null default 'active' check (status in ('active', 'trialing', 'past_due', 'canceled')),
  current_period_end timestamptz,
  payment_provider text,
  provider_customer_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.subscriptions is
  'Current billing state per parent. Never writable by the Flutter client — service role only.';

alter table public.subscriptions enable row level security;

create trigger set_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

create policy "Parents can view their own subscription"
  on public.subscriptions for select
  to authenticated
  using (parent_id = auth.uid());
