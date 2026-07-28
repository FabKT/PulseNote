-- Ultimate Audio Recorder — schema Supabase
-- A executer dans l'editeur SQL du projet Supabase (Dashboard > SQL Editor).
-- Cree les tables de synchronisation, active RLS (chaque utilisateur ne voit
-- que ses propres lignes) et les buckets Storage pour l'audio.

create table if not exists public.recordings (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  storage_path text,
  created_at timestamptz not null,
  duration_ms integer,
  trigger_source text,
  waveform jsonb not null default '[]'::jsonb,
  display_name text,
  is_favorite boolean not null default false,
  folder_id text,
  transcription text,
  summary text,
  updated_at timestamptz not null default now()
);

create table if not exists public.folders (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  pin_hash text,
  created_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.keywords (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text text not null,
  audio_sample_storage_path text,
  updated_at timestamptz not null default now()
);

create table if not exists public.schedules (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  start_hour integer not null,
  start_minute integer not null,
  end_hour integer not null,
  end_minute integer not null,
  mode text not null,
  keyword_ids jsonb not null default '[]'::jsonb,
  days_of_week jsonb not null default '[1,2,3,4,5,6,7]'::jsonb,
  recording_name text,
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.audio_playback_schedules (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  recording_id text not null,
  hour integer not null,
  minute integer not null,
  recurrence text not null,
  date date,
  weekdays jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  last_played_date_key text,
  updated_at timestamptz not null default now()
);

alter table public.recordings enable row level security;
alter table public.folders enable row level security;
alter table public.keywords enable row level security;
alter table public.schedules enable row level security;
alter table public.audio_playback_schedules enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['recordings', 'folders', 'keywords', 'schedules', 'audio_playback_schedules']
  loop
    execute format(
      'drop policy if exists "owner_full_access" on public.%I;
       create policy "owner_full_access" on public.%I
         for all using (auth.uid() = user_id) with check (auth.uid() = user_id);',
      t, t
    );
  end loop;
end $$;

-- Buckets prives pour l'audio. Chaque objet est range sous {user_id}/...,
-- les policies Storage restreignent chaque utilisateur a son propre prefixe.
insert into storage.buckets (id, name, public)
values ('recordings-audio', 'recordings-audio', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('keyword-samples', 'keyword-samples', false)
on conflict (id) do nothing;

do $$
declare
  b text;
begin
  foreach b in array array['recordings-audio', 'keyword-samples']
  loop
    execute format(
      'drop policy if exists "owner_storage_access_%1$s" on storage.objects;
       create policy "owner_storage_access_%1$s" on storage.objects
         for all
         using (bucket_id = %2$L and auth.uid()::text = (storage.foldername(name))[1])
         with check (bucket_id = %2$L and auth.uid()::text = (storage.foldername(name))[1]);',
      replace(b, '-', '_'), b
    );
  end loop;
end $$;
