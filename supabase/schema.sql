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

create table if not exists public.user_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'plus', 'pro')),
  subscription_product_id text,
  purchase_token_hash text unique,
  subscription_expires_at timestamptz,
  credits_remaining integer not null default 0 check (credits_remaining >= 0),
  credits_reset_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.recordings enable row level security;
alter table public.folders enable row level security;
alter table public.keywords enable row level security;
alter table public.schedules enable row level security;
alter table public.audio_playback_schedules enable row level security;
-- Jeton Google Play de l'abonnement en cours : le backend le reverifie quand
-- la periode payee est echue, pour prendre en compte renouvellements et
-- resiliations sans attendre que l'app renvoie l'achat.
alter table public.user_entitlements add column if not exists purchase_token text;
alter table public.user_entitlements
  add column if not exists subscription_last_verified_at timestamptz;

alter table public.user_entitlements enable row level security;

drop policy if exists "owner_read_entitlement" on public.user_entitlements;
create policy "owner_read_entitlement" on public.user_entitlements
  for select using (auth.uid() = user_id);

-- Le jeton d'achat doit rester strictement cote serveur. Une politique RLS
-- limite les lignes, pas les colonnes : on retire donc la lecture globale et
-- on ne rend accessibles au client que les champs non sensibles.
revoke all on public.user_entitlements from anon;
revoke select on public.user_entitlements from authenticated;
grant select (
  user_id,
  tier,
  subscription_product_id,
  subscription_expires_at,
  credits_remaining,
  credits_reset_at,
  updated_at
) on public.user_entitlements to authenticated;

create or replace function public.consume_ai_credits(
  p_user_id uuid,
  p_amount integer
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining integer;
begin
  if p_amount <= 0 then
    raise exception 'invalid_credit_amount';
  end if;

  update public.user_entitlements
  set credits_remaining = case
        when credits_reset_at is not null and credits_reset_at <= now()
          then 1000 - p_amount
        else credits_remaining - p_amount
      end,
      credits_reset_at = case
        when credits_reset_at is not null and credits_reset_at <= now()
          then now() + interval '1 month'
        else credits_reset_at
      end,
      updated_at = now()
  where user_id = p_user_id
    and tier = 'pro'
    and case
      when credits_reset_at is not null and credits_reset_at <= now()
        then 1000
      else credits_remaining
    end >= p_amount
  returning credits_remaining into remaining;

  if remaining is null then
    raise exception 'insufficient_ai_credits';
  end if;
  return remaining;
end;
$$;

create or replace function public.refund_ai_credits(
  p_user_id uuid,
  p_amount integer
) returns void
language sql
security definer
set search_path = public
as $$
  update public.user_entitlements
  set credits_remaining = least(1000, credits_remaining + greatest(p_amount, 0)),
      updated_at = now()
  where user_id = p_user_id and tier = 'pro';
$$;

revoke all on function public.consume_ai_credits(uuid, integer) from public, anon, authenticated;
revoke all on function public.refund_ai_credits(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_ai_credits(uuid, integer) to service_role;
grant execute on function public.refund_ai_credits(uuid, integer) to service_role;

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

-- ---------------------------------------------------------------------------
-- Amis, messagerie et dossiers partages
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  username text,
  display_name text not null,
  avatar_url text,
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists username text;
update public.profiles
set username = left(
  coalesce(
    nullif(lower(regexp_replace(split_part(email, '@', 1), '[^a-zA-Z0-9._]', '', 'g')), ''),
    'utilisateur'
  ),
  16
) || '_' || left(replace(id::text, '-', ''), 6)
where username is null or trim(username) = '';
alter table public.profiles alter column username set not null;
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_username_format'
  ) then
    alter table public.profiles add constraint profiles_username_format
      check (username ~ '^[a-z0-9._]{3,24}$');
  end if;
end $$;

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users (id) on delete cascade,
  receiver_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (sender_id <> receiver_id),
  unique (sender_id, receiver_id)
);

create table if not exists public.friendships (
  user_a uuid not null references auth.users (id) on delete cascade,
  user_b uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a <> user_b)
);

create table if not exists public.folder_shares (
  id uuid primary key default gen_random_uuid(),
  folder_id text not null references public.folders (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  folder_name text not null,
  mode text not null check (mode in ('live', 'snapshot')),
  created_at timestamptz not null default now(),
  check (owner_id <> recipient_id)
);

create table if not exists public.folder_share_items (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references public.folder_shares (id) on delete cascade,
  source_recording_id text not null references public.recordings (id) on delete cascade,
  source_owner_id uuid not null references auth.users (id) on delete cascade,
  display_name text,
  storage_path text,
  duration_ms integer,
  recorded_at timestamptz not null,
  unique (share_id, source_recording_id)
);

create table if not exists public.friend_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users (id) on delete cascade,
  receiver_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('text', 'audio', 'folder')),
  body text,
  audio_path text,
  folder_share_id uuid references public.folder_shares (id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender_id <> receiver_id)
);

create index if not exists friend_messages_conversation_idx
  on public.friend_messages (sender_id, receiver_id, created_at);
create index if not exists folder_shares_participants_idx
  on public.folder_shares (owner_id, recipient_id);
create index if not exists recordings_folder_id_idx
  on public.recordings (folder_id);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'friend_messages'
  ) then
    alter publication supabase_realtime add table public.friend_messages;
  end if;
end $$;

alter table public.profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.folder_shares enable row level security;
alter table public.folder_share_items enable row level security;
alter table public.friend_messages enable row level security;

create or replace function public.are_friends(p_left uuid, p_right uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships
    where (user_a = p_left and user_b = p_right)
       or (user_a = p_right and user_b = p_left)
  );
$$;

drop function if exists public.find_profile_by_email(text);
drop function if exists public.find_profile_by_username(text);
drop function if exists public.list_friends();
drop function if exists public.list_friend_requests();

create function public.find_profile_by_username(p_username text)
returns table (id uuid, username text, display_name text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.profiles p
  where lower(p.username) = lower(trim(leading '@' from trim(p_username)))
    and p.id <> auth.uid()
  limit 1;
$$;

create function public.list_friends()
returns table (id uuid, username text, display_name text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.friendships f
  join public.profiles p
    on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
  where f.user_a = auth.uid() or f.user_b = auth.uid()
  order by lower(p.display_name), lower(p.username);
$$;

create function public.list_friend_requests()
returns table (
  request_id uuid,
  profile_id uuid,
  username text,
  display_name text,
  avatar_url text,
  incoming boolean,
  status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    r.receiver_id = auth.uid(),
    r.status,
    r.created_at
  from public.friend_requests r
  join public.profiles p
    on p.id = case when r.sender_id = auth.uid() then r.receiver_id else r.sender_id end
  where (r.sender_id = auth.uid() or r.receiver_id = auth.uid())
    and r.status = 'pending'
  order by r.created_at desc;
$$;

create or replace function public.set_my_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_username text := lower(trim(leading '@' from trim(p_username)));
  updated_profile public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if clean_username !~ '^[a-z0-9._]{3,24}$' then
    raise exception 'username_invalid';
  end if;

  begin
    update public.profiles
    set username = clean_username, updated_at = now()
    where id = auth.uid()
    returning * into updated_profile;
  exception when unique_violation then
    raise exception 'username_taken';
  end;

  if updated_profile.id is null then
    raise exception 'profile_not_found';
  end if;

  return jsonb_build_object(
    'id', updated_profile.id,
    'email', updated_profile.email,
    'username', updated_profile.username,
    'display_name', updated_profile.display_name,
    'avatar_url', updated_profile.avatar_url
  );
end;
$$;

create or replace function public.answer_friend_request(
  p_request_id uuid,
  p_accept boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.friend_requests%rowtype;
begin
  select * into request_row
  from public.friend_requests
  where id = p_request_id
    and receiver_id = auth.uid()
    and status = 'pending'
  for update;

  if request_row.id is null then
    raise exception 'friend_request_not_found';
  end if;

  update public.friend_requests
  set status = case when p_accept then 'accepted' else 'declined' end,
      updated_at = now()
  where id = p_request_id;

  if p_accept then
    insert into public.friendships (user_a, user_b)
    values (
      least(request_row.sender_id, request_row.receiver_id),
      greatest(request_row.sender_id, request_row.receiver_id)
    )
    on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.are_friends(uuid, uuid) from public, anon;
revoke all on function public.find_profile_by_username(text) from public, anon;
revoke all on function public.list_friends() from public, anon;
revoke all on function public.list_friend_requests() from public, anon;
revoke all on function public.answer_friend_request(uuid, boolean) from public, anon;
revoke all on function public.set_my_username(text) from public, anon;
grant execute on function public.are_friends(uuid, uuid) to authenticated;
grant execute on function public.find_profile_by_username(text) to authenticated;
grant execute on function public.list_friends() to authenticated;
grant execute on function public.list_friend_requests() to authenticated;
grant execute on function public.answer_friend_request(uuid, boolean) to authenticated;
grant execute on function public.set_my_username(text) to authenticated;

drop policy if exists "profile_self_write" on public.profiles;
create policy "profile_self_write" on public.profiles
  for all using (id = auth.uid())
  with check (
    id = auth.uid()
    -- Empeche de reserver l'email (unique) d'un autre utilisateur.
    and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
drop policy if exists "profile_friend_read" on public.profiles;
create policy "profile_friend_read" on public.profiles
  for select using (id = auth.uid() or public.are_friends(id, auth.uid()));

drop policy if exists "friend_request_participant_read" on public.friend_requests;
create policy "friend_request_participant_read" on public.friend_requests
  for select using (auth.uid() in (sender_id, receiver_id));
drop policy if exists "friend_request_sender_insert" on public.friend_requests;
create policy "friend_request_sender_insert" on public.friend_requests
  for insert with check (
    sender_id = auth.uid()
    and not public.are_friends(sender_id, receiver_id)
  );

drop policy if exists "friendship_participant_read" on public.friendships;
create policy "friendship_participant_read" on public.friendships
  for select using (auth.uid() in (user_a, user_b));

drop policy if exists "folder_share_participant_read" on public.folder_shares;
create policy "folder_share_participant_read" on public.folder_shares
  for select using (auth.uid() in (owner_id, recipient_id));
-- Ni UPDATE ni DELETE pour les utilisateurs : on ne sort d'un partage qu'en
-- le quittant via le backend (POST /shares/:id/leave), qui donne d'abord a
-- l'autre partie une copie independante du contenu.
drop policy if exists "folder_share_owner_write" on public.folder_shares;
drop policy if exists "folder_share_owner_delete_snapshot" on public.folder_shares;
drop policy if exists "folder_share_owner_insert" on public.folder_shares;
create policy "folder_share_owner_insert" on public.folder_shares
  for insert with check (
    owner_id = auth.uid()
    and public.are_friends(owner_id, recipient_id)
    -- Sans cette verification, on pouvait "partager" le dossier d'un tiers
    -- et lire ses enregistrements via shared_recording_read.
    and exists (
      select 1 from public.folders f
      where f.id = folder_id and f.user_id = auth.uid()
    )
  );

drop policy if exists "folder_share_item_participant_read" on public.folder_share_items;
create policy "folder_share_item_participant_read" on public.folder_share_items
  for select using (
    exists (
      select 1 from public.folder_shares s
      where s.id = share_id and auth.uid() in (s.owner_id, s.recipient_id)
    )
  );
drop policy if exists "folder_share_item_owner_insert" on public.folder_share_items;
create policy "folder_share_item_owner_insert" on public.folder_share_items
  for insert with check (
    source_owner_id = auth.uid()
    and exists (
      select 1 from public.folder_shares s
      where s.id = share_id and s.owner_id = auth.uid()
    )
    -- Seuls ses propres enregistrements peuvent etre partages. Le fichier
    -- audio reste protege par shared_recording_storage_read, qui se base sur
    -- recordings.storage_path et non sur la copie stockee ici.
    and exists (
      select 1 from public.recordings r
      where r.id = source_recording_id
        and r.user_id = auth.uid()
    )
  );

drop policy if exists "friend_message_participant_read" on public.friend_messages;
create policy "friend_message_participant_read" on public.friend_messages
  for select using (auth.uid() in (sender_id, receiver_id));
drop policy if exists "friend_message_sender_insert" on public.friend_messages;
create policy "friend_message_sender_insert" on public.friend_messages
  for insert with check (
    sender_id = auth.uid()
    and public.are_friends(sender_id, receiver_id)
    -- Un message audio ne peut pointer que vers un fichier de l'expediteur.
    and (audio_path is null or split_part(audio_path, '/', 1) = auth.uid()::text)
    and (
      folder_share_id is null
      or exists (
        select 1 from public.folder_shares s
        where s.id = folder_share_id
          and s.owner_id = auth.uid()
          and s.recipient_id = receiver_id
      )
    )
  );
drop policy if exists "friend_message_recipient_update" on public.friend_messages;
create policy "friend_message_recipient_update" on public.friend_messages
  for update using (receiver_id = auth.uid())
  with check (receiver_id = auth.uid());
-- Le destinataire peut seulement marquer un message comme lu.
revoke update on public.friend_messages from anon, authenticated;
grant update (read_at) on public.friend_messages to authenticated;

drop policy if exists "shared_folder_read" on public.folders;
create policy "shared_folder_read" on public.folders
  for select using (
    exists (
      select 1 from public.folder_shares s
      where s.folder_id = folders.id
        and auth.uid() in (s.owner_id, s.recipient_id)
    )
  );

drop policy if exists "shared_recording_read" on public.recordings;
create policy "shared_recording_read" on public.recordings
  for select using (
    exists (
      select 1 from public.folder_shares s
      where s.mode = 'live'
        and s.folder_id = recordings.folder_id
        and auth.uid() in (s.owner_id, s.recipient_id)
    )
    or exists (
      select 1
      from public.folder_share_items i
      join public.folder_shares s on s.id = i.share_id
      where i.source_recording_id = recordings.id
        and auth.uid() in (s.owner_id, s.recipient_id)
    )
  );

-- Un enregistrement ne peut etre range que dans un dossier dont on fait
-- partie : le sien, ou un dossier partage en direct avec soi. Un dossier
-- encore absent du serveur (cree hors ligne, pas encore synchronise) est
-- accepte : il n'appartient a personne et n'est partage avec personne.
-- security definer : la verification doit voir les dossiers des autres,
-- que la RLS masque a l'appelant.
create or replace function public.can_file_into_folder(p_folder_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_folder_id is null
    or not exists (select 1 from public.folders f where f.id = p_folder_id)
    or exists (
      select 1 from public.folders f
      where f.id = p_folder_id and f.user_id = auth.uid()
    )
    or exists (
      select 1 from public.folder_shares s
      where s.folder_id = p_folder_id
        and s.mode = 'live'
        and s.recipient_id = auth.uid()
    );
$$;

-- Appelee uniquement par le trigger ci-dessous : non exposee aux clients,
-- elle revelerait sinon l'existence des dossiers des autres.
revoke all on function public.can_file_into_folder(text) from public, anon, authenticated;

-- Seul un CHANGEMENT de dossier est controle. Un enregistrement qui reste
-- dans son dossier peut toujours etre modifie : apres la fin d'un partage en
-- direct, l'ami garde la main sur les enregistrements qu'il y avait ajoutes.
-- L'upsert de la synchronisation passe par INSERT ... ON CONFLICT : on compare
-- donc aussi a la ligne existante lors d'un INSERT.
create or replace function public.enforce_recording_folder_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  previous_folder text;
  has_previous boolean;
begin
  -- service_role / editeur SQL : pas d'utilisateur, pas de controle.
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    previous_folder := old.folder_id;
    has_previous := true;
  else
    select r.folder_id, true into previous_folder, has_previous
    from public.recordings r
    where r.id = new.id and r.user_id = new.user_id;
  end if;

  if coalesce(has_previous, false)
     and new.folder_id is not distinct from previous_folder then
    return new;
  end if;

  if not public.can_file_into_folder(new.folder_id) then
    raise exception 'folder_not_allowed';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_recording_folder_membership() from public, anon, authenticated;

drop policy if exists "recording_folder_membership_insert" on public.recordings;
drop policy if exists "recording_folder_membership_update" on public.recordings;
drop trigger if exists recordings_folder_membership on public.recordings;
create trigger recordings_folder_membership
  before insert or update on public.recordings
  for each row execute function public.enforce_recording_folder_membership();

-- Un dossier partage ne peut pas etre supprime : chacun peut seulement le
-- quitter (POST /shares/:id/leave sur le backend), l'autre partie en gardant
-- une copie independante. Le backend (service_role) et la suppression de
-- compte n'ont pas d'auth.uid() et ne sont pas bloques.
drop function if exists public.end_live_share(uuid);
create or replace function public.prevent_shared_folder_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and exists (select 1 from public.folder_shares s where s.folder_id = old.id) then
    raise exception 'shared_folder_cannot_be_deleted';
  end if;
  return old;
end;
$$;

revoke all on function public.prevent_shared_folder_delete() from public, anon, authenticated;

drop trigger if exists folders_prevent_shared_delete on public.folders;
create trigger folders_prevent_shared_delete
  before delete on public.folders
  for each row execute function public.prevent_shared_folder_delete();

insert into storage.buckets (id, name, public)
values ('friend-audio', 'friend-audio', false)
on conflict (id) do nothing;

drop policy if exists "friend_audio_sender_insert" on storage.objects;
create policy "friend_audio_sender_insert" on storage.objects
  for insert with check (
    bucket_id = 'friend-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
drop policy if exists "friend_audio_participant_read" on storage.objects;
create policy "friend_audio_participant_read" on storage.objects
  for select using (
    bucket_id = 'friend-audio'
    and exists (
      select 1 from public.friend_messages m
      where m.audio_path = name
        and (storage.foldername(name))[1] = m.sender_id::text
        and auth.uid() in (m.sender_id, m.receiver_id)
    )
  );
drop policy if exists "friend_audio_sender_delete" on storage.objects;
create policy "friend_audio_sender_delete" on storage.objects
  for delete using (
    bucket_id = 'friend-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "shared_recording_storage_read" on storage.objects;
create policy "shared_recording_storage_read" on storage.objects
  for select using (
    bucket_id = 'recordings-audio'
    and exists (
      select 1 from public.recordings r
      where r.storage_path = name
        -- Une ligne recordings ne donne acces qu'aux fichiers de son
        -- proprietaire : sinon on pouvait creer une ligne pointant vers le
        -- fichier d'un tiers et la partager pour le lire.
        and (storage.foldername(name))[1] = r.user_id::text
        and (
          exists (
            select 1 from public.folder_shares s
            where s.mode = 'live'
              and s.folder_id = r.folder_id
              and auth.uid() in (s.owner_id, s.recipient_id)
          )
          or exists (
            select 1
            from public.folder_share_items i
            join public.folder_shares s on s.id = i.share_id
            where i.source_recording_id = r.id
              and auth.uid() in (s.owner_id, s.recipient_id)
          )
        )
    )
  );

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
