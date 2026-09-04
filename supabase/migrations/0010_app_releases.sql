create table public.app_releases (
  id            uuid primary key default gen_random_uuid(),
  platform      text not null check (platform in ('android','ios')),
  version_name  text not null,      -- '1.2.0'
  build_number  int  not null,      -- 14
  min_supported int  not null default 1,
  download_url  text,               -- Google Drive / iCloud link for the APK
  release_notes text not null default '',
  released_at   timestamptz not null default now()
);
create index app_releases_latest_idx on public.app_releases(platform, build_number desc);

alter table public.app_releases enable row level security;

-- ── app_releases: everyone reads, nobody writes from the app ──
create policy rel_select on public.app_releases for select to authenticated using (true);
