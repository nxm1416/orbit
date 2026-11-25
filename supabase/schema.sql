-- =====================================================================
-- Orbit — Supabase データベース設定
-- Supabase の「SQL Editor」にこのファイルの中身をすべて貼り付けて「Run」を押してください。
-- 何度実行しても大丈夫なように作ってあります（既存のデータは消えません）。
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- 共通の関数 ----------
create or replace function public.now_ms() returns bigint language sql stable as $$
  select (extract(epoch from clock_timestamp()) * 1000)::bigint
$$;

-- ---------- テーブル ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  handle text not null,
  bio text not null default '',
  link text not null default '',
  color text not null default '',
  avatar text not null default '',
  header text not null default '',
  pinned text not null default '',
  locked boolean not null default false,
  at bigint not null default public.now_ms(),
  last_seen bigint not null default 0,
  presence text not null default 'auto'
);
create unique index if not exists profiles_handle_lower on public.profiles (lower(handle));

create table if not exists public.admins (uid uuid primary key references auth.users(id) on delete cascade);

create table if not exists public.posts (
  id text primary key,
  author uuid not null references auth.users(id) on delete cascade,
  text text not null default '',
  at bigint not null default public.now_ms(),
  edited_at bigint not null default 0,
  reply_to text,
  quote_of text,
  scope text not null default 'all',
  media jsonb not null default '[]',
  aud text not null default 'all',
  poll jsonb,
  link jsonb,
  nsfw boolean not null default false,
  comm text
);
create index if not exists posts_at on public.posts (at desc);
create index if not exists posts_author on public.posts (author);

create table if not exists public.likes (id text primary key, post text not null, user_id uuid not null references auth.users(id) on delete cascade, at bigint not null default public.now_ms());
create table if not exists public.reposts (id text primary key, post text not null, user_id uuid not null references auth.users(id) on delete cascade, at bigint not null default public.now_ms());
create table if not exists public.follows (id text primary key, from_id uuid not null references auth.users(id) on delete cascade, to_id uuid not null references auth.users(id) on delete cascade, at bigint not null default public.now_ms());
create table if not exists public.freqs (id text primary key, from_id uuid not null references auth.users(id) on delete cascade, to_id uuid not null references auth.users(id) on delete cascade, at bigint not null default public.now_ms());
create table if not exists public.blocks (id uuid primary key references auth.users(id) on delete cascade, list jsonb not null default '[]');
create table if not exists public.private_docs (uid uuid not null references auth.users(id) on delete cascade, key text not null, json jsonb not null default '{}', primary key (uid, key));
create table if not exists public.reports (id uuid primary key references auth.users(id) on delete cascade, items jsonb not null default '[]');
create table if not exists public.report_status (id text primary key, status text not null default 'open', by_id uuid, result text not null default '', at bigint not null default public.now_ms());
create table if not exists public.hidden (id text primary key, by_id uuid, at bigint not null default public.now_ms(), reason text not null default '');
create table if not exists public.suspended (id uuid primary key references auth.users(id) on delete cascade, kind text not null default 'temp', until bigint not null default 0, reason text not null default '', by_id uuid, at bigint not null default public.now_ms());
create table if not exists public.announcements (id text primary key, text text not null default '', kind text not null default 'info', at bigint not null default public.now_ms(), by_id uuid, to_id uuid);
create table if not exists public.modlog (id text primary key, by_id uuid, action text not null default '', note text not null default '', at bigint not null default public.now_ms());
create table if not exists public.dms (id text primary key, conv text not null, from_id uuid not null references auth.users(id) on delete cascade, to_id uuid not null references auth.users(id) on delete cascade, text text not null default '', at bigint not null default public.now_ms(), media jsonb not null default '[]', read_at bigint not null default 0, reacts jsonb not null default '{}');
create index if not exists dms_conv on public.dms (conv);
alter table public.dms add column if not exists reply_to text;
alter table public.dms add column if not exists edited_at bigint not null default 0;
create table if not exists public.votes (post text not null, user_id uuid not null references auth.users(id) on delete cascade, choice int not null, at bigint not null default public.now_ms(), primary key (post, user_id));
create table if not exists public.communities (id text primary key, name text not null, descr text not null default '', owner uuid not null references auth.users(id) on delete cascade, color text not null default '', at bigint not null default public.now_ms());
create table if not exists public.members (id text primary key, comm text not null references public.communities(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade, role text not null default 'member', at bigint not null default public.now_ms());
create table if not exists public.scheduled (id text primary key, author uuid not null references auth.users(id) on delete cascade, json jsonb not null, at bigint not null, created bigint not null default public.now_ms());

-- ---------- 判定用の関数 ----------
create or replace function public.uid() returns uuid language sql stable as $$ select auth.uid() $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where uid = auth.uid())
$$;
create or replace function public.is_susp(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.suspended s where s.id = u and (s.kind = 'perm' or s.until <= 0 or s.until > public.now_ms()))
$$;
create or replace function public.blocked(blocker uuid, target uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks b where b.id = blocker and b.list ? target::text)
$$;
create or replace function public.follows_(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.follows f where f.from_id = a and f.to_id = b)
$$;
create or replace function public.is_locked(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select locked from public.profiles where id = u), false)
$$;
create or replace function public.is_member(c text, u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members m where m.comm = c and m.user_id = u)
$$;
create or replace function public.can_see(p_author uuid, p_aud text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select case
    when public.is_admin() or p_author = auth.uid() then true
    when exists (select 1 from public.hidden h where h.id = p_id) then false
    when public.is_susp(p_author) then false
    when p_aud = 'followers' or public.is_locked(p_author) then public.follows_(auth.uid(), p_author)
    else true end
$$;
create or replace function public.is_public_post(p_author uuid, p_aud text) returns boolean language sql stable security definer set search_path = public as $$
  select p_aud <> 'followers' and not public.is_locked(p_author)
$$;
create or replace function public.fail(msg text) returns void language plpgsql as $$ begin raise exception '%', msg using errcode = 'P0001'; end $$;

-- 2段階認証：確認済みのログインかどうか（詳しくは下の「ログインと 2段階認証」）
create table if not exists public.strong_sessions (session_id text primary key, uid uuid not null references auth.users(id) on delete cascade, at bigint not null default public.now_ms());
alter table public.strong_sessions enable row level security;
create or replace function public.strong_session() returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    exists (select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end) x
            where coalesce(x ->> 'method', '') not in ('', 'password', 'anonymous'))
    or exists (select 1 from public.strong_sessions s where s.session_id = auth.jwt() ->> 'session_id' and s.uid = auth.uid()))
$$;
create or replace function public.need_strong() returns void language plpgsql stable as $$
begin if not public.strong_session() then raise exception 'もう一度ログインしてください' using errcode = 'P0001'; end if; end $$;

-- ---------- 新規登録時にプロフィールを作る（最初の登録者は管理者） ----------
create or replace function public.on_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare h text; n text;
begin
  h := coalesce(new.raw_user_meta_data->>'handle', '');
  if h !~ '^[A-Za-z0-9_]{3,20}$' or exists (select 1 from public.profiles where lower(handle) = lower(h)) then
    h := 'u' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;
  if exists (select 1 from public.admins) and not public.signup_open() then raise exception '現在、新規登録を受け付けていません' using errcode = 'P0001'; end if;
  n := left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), h), 40);
  insert into public.profiles (id, name, handle) values (new.id, n, h) on conflict (id) do nothing;
  if not exists (select 1 from public.admins) then insert into public.admins (uid) values (new.id); end if;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.on_new_user();

-- ---------- 投稿のチェック（文字数・投票・返信先・連続投稿など） ----------
create or replace function public.posts_check() returns trigger language plpgsql security definer set search_path = public as $$
declare par record; q record; ops jsonb; dur bigint; me uuid := auth.uid(); h text;
begin
  if tg_op = 'INSERT' then
    if me is null then perform public.fail('ログインしてください'); end if;
    new.author := me;
    new.at := public.now_ms();
    new.edited_at := 0;
    if public.is_susp(me) and not public.is_admin() then perform public.fail('アカウントが凍結中のため投稿できません'); end if;
  else
    if old.author <> me and not public.is_admin() then perform public.fail('この操作は許可されていません'); end if;
    new.id := old.id; new.author := old.author; new.at := old.at; new.reply_to := old.reply_to; new.quote_of := old.quote_of;
    new.poll := old.poll; new.aud := old.aud; new.comm := old.comm; new.scope := old.scope; new.link := old.link;
    if old.author = me and (new.text is distinct from old.text or new.media is distinct from old.media) then new.edited_at := public.now_ms(); end if;
  end if;
  new.text := btrim(coalesce(new.text, ''));
  if char_length(new.text) > 280 then perform public.fail('280文字以内で入力してください'); end if;
  if public.ng_hit(new.text) and not public.is_admin() then perform public.fail('禁止されている語句が含まれています'); end if;
  if jsonb_typeof(new.media) <> 'array' then new.media := '[]'; end if;
  if jsonb_array_length(new.media) > 4 then perform public.fail('画像は4枚までです'); end if;
  if new.text ~* '(^|\s)[#＃](R-?18G?|NSFW|成人向け|センシティブ)(\s|$)' then new.nsfw := true; end if;
  if tg_op = 'UPDATE' then
    if new.text = '' and jsonb_array_length(new.media) = 0 and new.quote_of is null and new.poll is null then perform public.fail('本文を入力してください'); end if;
    return new;
  end if;
  new.scope := case when new.scope in ('all', 'following', 'mentioned') then new.scope else 'all' end;
  new.aud := case when new.aud = 'followers' then 'followers' else 'all' end;
  if new.poll is not null and jsonb_typeof(new.poll) = 'object' then
    select coalesce(jsonb_agg(left(btrim(v), 25)), '[]') into ops from jsonb_array_elements_text(coalesce(new.poll->'opts', '[]')) v where btrim(v) <> '';
    if jsonb_array_length(ops) < 2 then perform public.fail('投票の選択肢は2つ以上入力してください'); end if;
    if jsonb_array_length(ops) > 4 then ops := (select jsonb_agg(x) from (select x from jsonb_array_elements(ops) x limit 4) t); end if;
    dur := coalesce((new.poll->>'dur')::bigint, 0);
    if dur not in (3600, 21600, 86400, 259200, 604800) then perform public.fail('投票期間が正しくありません'); end if;
    if jsonb_array_length(new.media) > 0 then perform public.fail('投票と画像・動画は同時に投稿できません'); end if;
    new.poll := jsonb_build_object('opts', ops, 'ends', public.now_ms() + dur * 1000);
  else new.poll := null; end if;
  if new.text = '' and jsonb_array_length(new.media) = 0 and new.quote_of is null and new.poll is null then perform public.fail('本文を入力してください'); end if;
  if current_setting('orbit.sched', true) = 'on' then null;
  elsif (select count(*) from public.posts where author = me and at > public.now_ms() - 60000) >= 5 then perform public.fail('連続投稿が多すぎます。少し待ってください');
  elsif new.text <> '' and exists (select 1 from public.posts where author = me and reply_to is null and text = new.text and at > public.now_ms() - 3600000) then perform public.fail('同じ内容を続けて投稿することはできません'); end if;
  if new.reply_to is not null then
    select * into par from public.posts where id = new.reply_to;
    if not found then perform public.fail('返信先の投稿が見つかりません'); end if;
    if par.author <> me then
      if public.blocked(par.author, me) or public.blocked(me, par.author) or not public.can_see(par.author, par.aud, par.id) then perform public.fail('この投稿には返信できません'); end if;
      if par.scope = 'following' and not public.follows_(par.author, me) then perform public.fail('この投稿に返信できるのは、投稿者がフォローしている人だけです'); end if;
      if par.scope = 'mentioned' then
        select lower(handle) into h from public.profiles where id = me;
        if position(('@' || h) in lower(par.text)) = 0 then perform public.fail('この投稿に返信できるのは、@で指定された人だけです'); end if;
      end if;
    end if;
    if par.comm is not null then new.comm := par.comm; end if;
  end if;
  if new.quote_of is not null then
    select * into q from public.posts where id = new.quote_of;
    if not found then perform public.fail('引用元の投稿が見つかりません'); end if;
    if q.author <> me and not public.is_public_post(q.author, q.aud) then perform public.fail('この投稿は引用できません'); end if;
  end if;
  if new.comm is not null and new.comm <> '' then
    if not exists (select 1 from public.communities where id = new.comm) then perform public.fail('コミュニティが見つかりません'); end if;
    if not public.is_member(new.comm, me) then perform public.fail('コミュニティに参加すると投稿できます'); end if;
    new.aud := 'all';
  else new.comm := null; end if;
  return new;
end $$;
drop trigger if exists posts_check on public.posts;
create trigger posts_check before insert or update on public.posts for each row execute function public.posts_check();

create or replace function public.react_check() returns trigger language plpgsql security definer set search_path = public as $$
declare p record; me uuid := auth.uid();
begin
  select * into p from public.posts where id = new.post;
  if not found then perform public.fail('投稿が見つかりません'); end if;
  new.user_id := me; new.id := new.post || '__' || me::text; new.at := public.now_ms();
  if public.is_susp(me) then perform public.fail('アカウントが凍結中です'); end if;
  if public.blocked(p.author, me) or not public.can_see(p.author, p.aud, p.id) then perform public.fail('この投稿には反応できません'); end if;
  if tg_table_name = 'reposts' and p.author <> me and not public.is_public_post(p.author, p.aud) then perform public.fail('この投稿はリポストできません'); end if;
  if tg_table_name = 'likes' and (select count(*) from public.likes where user_id = me and at > public.now_ms() - 60000) >= 40 then perform public.fail('いいねの操作が多すぎます'); end if;
  return new;
end $$;
drop trigger if exists likes_check on public.likes;
create trigger likes_check before insert on public.likes for each row execute function public.react_check();
drop trigger if exists reposts_check on public.reposts;
create trigger reposts_check before insert on public.reposts for each row execute function public.react_check();

create or replace function public.follows_check() returns trigger language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if current_setting('orbit.approving', true) = 'on' then return new; end if;
  new.from_id := me; new.id := me::text || '__' || new.to_id::text; new.at := public.now_ms();
  if new.to_id = me then perform public.fail('この操作は許可されていません'); end if;
  if public.is_susp(me) then perform public.fail('アカウントが凍結中です'); end if;
  if public.blocked(new.to_id, me) or public.blocked(me, new.to_id) then perform public.fail('このユーザーはフォローできません'); end if;
  if public.is_locked(new.to_id) then perform public.fail('鍵アカウントをフォローするには、フォローリクエストを送ってください'); end if;
  if (select count(*) from public.follows where from_id = me and at > public.now_ms() - 600000) >= 30 then perform public.fail('短時間に多くのユーザーをフォローすることはできません'); end if;
  return new;
end $$;
drop trigger if exists follows_check on public.follows;
create trigger follows_check before insert on public.follows for each row execute function public.follows_check();

create or replace function public.profiles_check() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.id <> auth.uid() and not public.is_admin() then perform public.fail('この操作は許可されていません'); end if;
  new.id := old.id; new.at := old.at;
  new.handle := btrim(new.handle);
  if new.handle !~ '^[A-Za-z0-9_]{3,20}$' then perform public.fail('ユーザーIDは3〜20文字の英数字と _ で指定してください'); end if;
  if exists (select 1 from public.profiles where lower(handle) = lower(new.handle) and id <> new.id) then perform public.fail('このユーザーIDは使われています'); end if;
  new.name := left(coalesce(nullif(btrim(new.name), ''), new.handle), 40);
  new.bio := left(coalesce(new.bio, ''), 160);
  if public.ng_hit(new.name || ' ' || new.handle || ' ' || new.bio) and not public.is_admin() then perform public.fail('禁止されている語句が含まれています'); end if;
  if new.link !~ '^https://' then new.link := ''; end if; new.link := left(new.link, 200);
  if new.color !~ '^#[0-9a-fA-F]{6}$' then new.color := ''; end if;
  if new.presence not in ('auto', 'busy', 'offline') then new.presence := 'auto'; end if;
  if old.locked and not new.locked then
    perform set_config('orbit.approving', 'on', true);
    insert into public.follows (id, from_id, to_id, at) select f.from_id::text || '__' || f.to_id::text, f.from_id, f.to_id, public.now_ms() from public.freqs f where f.to_id = new.id on conflict do nothing;
    delete from public.freqs where to_id = new.id;
    perform set_config('orbit.approving', 'off', true);
  end if;
  return new;
end $$;
drop trigger if exists profiles_check on public.profiles;
create trigger profiles_check before update on public.profiles for each row execute function public.profiles_check();

create or replace function public.reports_check() returns trigger language plpgsql security definer set search_path = public as $$
declare it jsonb; out jsonb := '[]'; m record;
begin
  new.id := auth.uid();
  for it in select * from jsonb_array_elements(coalesce(new.items, '[]')) loop
    if it->>'kind' = 'dm' then
      select * into m from public.dms where id = it->>'target';
      if found and (m.from_id = auth.uid() or m.to_id = auth.uid()) then
        it := it || jsonb_build_object('who', m.from_id::text, 'snap', left(m.text, 500));
      end if;
    end if;
    out := out || jsonb_build_array(it);
  end loop;
  new.items := (select coalesce(jsonb_agg(x), '[]') from (select x from jsonb_array_elements(out) x offset greatest(jsonb_array_length(out) - 200, 0)) t);
  return new;
end $$;
drop trigger if exists reports_check on public.reports;
create trigger reports_check before insert or update on public.reports for each row execute function public.reports_check();

-- 管理者の操作には作業者を自動で記録
create or replace function public.stamp_by() returns trigger language plpgsql as $$ begin new.by_id := auth.uid(); if new.at is null or new.at = 0 then new.at := public.now_ms(); end if; return new; end $$;
do $$ declare t text; begin
  foreach t in array array['report_status', 'hidden', 'suspended', 'announcements', 'modlog'] loop
    execute format('drop trigger if exists stamp_by on public.%I', t);
    execute format('create trigger stamp_by before insert or update on public.%I for each row execute function public.stamp_by()', t);
  end loop;
end $$;

-- ---------- サイト設定（新規登録の受付・メンテナンス・NGワード）と認証バッジ ----------
create table if not exists public.site_settings (key text primary key, value jsonb not null, by_id uuid, at bigint not null default public.now_ms());
create table if not exists public.badges (id uuid primary key references auth.users(id) on delete cascade, kind text not null default 'verified', by_id uuid, at bigint not null default public.now_ms());
alter table public.badges drop constraint if exists badges_kind_check;
alter table public.badges add constraint badges_kind_check check (kind in ('verified', 'official'));

create or replace function public.site_get(k text) returns jsonb language sql stable security definer set search_path = public as $$
  select value from public.site_settings where key = k
$$;
create or replace function public.signup_open() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((public.site_get('signup') #>> '{}')::boolean, true)
$$;
create or replace function public.maintenance() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((public.site_get('maintenance') #>> '{}')::boolean, false)
$$;
create or replace function public.ng_hit(t text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(public.site_get('ngwords')) = 'array' then public.site_get('ngwords') else '[]'::jsonb end) w
                 where length(btrim(w)) > 0 and position(lower(btrim(w)) in lower(coalesce(t, ''))) > 0)
$$;
create or replace function public.need_open() returns void language plpgsql stable security definer set search_path = public as $$
begin if public.maintenance() and not public.is_admin() then raise exception 'メンテナンス中のため、現在は閲覧のみできます' using errcode = 'P0001'; end if; end $$;
-- ログイン前でも見られる情報（新規登録を受け付けているか・メンテナンス中か）
create or replace function public.site_public() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('signup', public.signup_open(), 'maintenance', public.maintenance(), 'message', coalesce(public.site_get('maint_msg') #>> '{}', ''))
$$;

do $$ declare t text; begin
  drop trigger if exists stamp_by on public.badges;
  create trigger stamp_by before insert or update on public.badges for each row execute function public.stamp_by();
  drop trigger if exists stamp_by on public.site_settings;
  create trigger stamp_by before insert or update on public.site_settings for each row execute function public.stamp_by();
end $$;

-- ---------- 管理者向けの処理 ----------
create or replace function public.need_admin() returns void language plpgsql stable security definer set search_path = public as $$
begin perform public.need_strong(); if not public.is_admin() then raise exception 'この操作は許可されていません' using errcode = 'P0001'; end if; end $$;

create or replace function public.admin_user_info(target uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare u record; g record;
begin
  perform public.need_admin();
  select id, email, created_at, last_sign_in_at, email_confirmed_at into u from auth.users where id = target;
  if not found then return null; end if;
  select * into g from public.login_guard where uid = target;
  return jsonb_build_object('email', u.email,
    'created', (extract(epoch from u.created_at) * 1000)::bigint,
    'lastSignIn', coalesce((extract(epoch from u.last_sign_in_at) * 1000)::bigint, 0),
    'confirmed', u.email_confirmed_at is not null,
    'admin', exists (select 1 from public.admins where uid = target),
    'lockedUntil', coalesce(g.until, 0), 'fails', coalesce(g.fails, 0),
    'devices', (select count(*) from public.trusted_devices where uid = target and expires > public.now_ms()),
    'posts', (select count(*) from public.posts where author = target),
    'dms', (select count(*) from public.dms where from_id = target),
    'push', (select count(*) from public.push_subs where uid = target));
end $$;

create or replace function public.admin_set_admin(target uuid, on_ boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_admin();
  if on_ then insert into public.admins (uid) values (target) on conflict do nothing;
  else
    if (select count(*) from public.admins) <= 1 then perform public.fail('最後の管理者は外せません'); end if;
    delete from public.admins where uid = target;
  end if;
end $$;

create or replace function public.admin_unlock(target uuid) returns void language plpgsql security definer set search_path = public as $$
begin perform public.need_admin(); delete from public.login_guard where uid = target; end $$;

create or replace function public.admin_forget_devices(target uuid) returns void language plpgsql security definer set search_path = public as $$
begin perform public.need_admin(); delete from public.trusted_devices where uid = target; delete from public.strong_sessions where uid = target; end $$;

create or replace function public.admin_delete_posts(target uuid) returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin perform public.need_admin(); delete from public.posts where author = target; get diagnostics n = row_count; return n; end $$;

create or replace function public.admin_delete_user(target uuid) returns void language plpgsql security definer set search_path = public, auth as $$
begin
  perform public.need_admin();
  if target = auth.uid() then perform public.fail('自分のアカウントは設定画面から削除してください'); end if;
  if exists (select 1 from public.admins where uid = target) then perform public.fail('管理者のアカウントは削除できません。先に管理者から外してください'); end if;
  delete from public.posts where comm in (select id from public.communities where owner = target);
  delete from auth.users where id = target;
end $$;

create or replace function public.admin_comm_owner(c_id text, target uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_admin();
  if not exists (select 1 from public.communities where id = c_id) then perform public.fail('コミュニティが見つかりません'); end if;
  if not exists (select 1 from public.profiles where id = target) then perform public.fail('ユーザーが見つかりません'); end if;
  update public.members set role = 'member' where comm = c_id and role = 'owner';
  insert into public.members (id, comm, user_id, role) values (c_id || '__' || target::text, c_id, target, 'owner')
  on conflict (id) do update set role = 'owner';
  update public.communities set owner = target where id = c_id;
end $$;

-- ---------- プッシュ通知 ----------
-- push_subs: 端末ごとの通知の宛先 / push_config: 通知用の鍵など（だれも直接は読めない。Edge Function だけが使う）
create table if not exists public.push_subs (endpoint text not null, uid uuid not null references auth.users(id) on delete cascade, p256dh text not null, auth text not null, ua text not null default '', at bigint not null default public.now_ms(), primary key (endpoint, uid));
create index if not exists push_subs_uid on public.push_subs (uid);
create table if not exists public.push_config (key text primary key, value text not null);
alter table public.push_subs enable row level security;
alter table public.push_config enable row level security;
insert into public.push_config (key, value) values ('hook_secret', encode(extensions.gen_random_bytes(24), 'hex')) on conflict do nothing;

-- 通知を Edge Function に頼む（pg_net で非同期に送るので、投稿などの処理は待たされない）
create or replace function public.push_send(target uuid, kind text, actor uuid, ref text, snippet text) returns void language plpgsql security definer set search_path = public as $$
declare u text; sec text;
begin
  if target is null or target = actor then return; end if;
  if not exists (select 1 from public.push_subs where uid = target) then return; end if;
  if public.blocked(target, actor) then return; end if;
  select value into u from public.push_config where key = 'fn_url';
  select value into sec from public.push_config where key = 'hook_secret';
  if u is null or sec is null then return; end if;
  perform net.http_post(url := u, body := jsonb_build_object('target', target, 'kind', kind, 'actor', actor, 'ref', ref, 'snippet', left(coalesce(snippet, ''), 120)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-orbit-secret', sec), timeout_milliseconds := 5000);
exception when others then raise warning 'プッシュ通知を送れませんでした: %', sqlerrm;
end $$;
revoke all on function public.push_send(uuid, text, uuid, text, text) from public, anon, authenticated;

create or replace function public.push_on_change() returns trigger language plpgsql security definer set search_path = public as $$
declare p record; h text; pub boolean;
begin
  if tg_table_name in ('likes', 'reposts') then
    select author, text, aud into p from public.posts where id = new.post;
    if found then perform public.push_send(p.author, case when tg_table_name = 'likes' then 'like' else 'repost' end, new.user_id, new.post, case when public.is_public_post(p.author, p.aud) then p.text end); end if;
  elsif tg_table_name = 'follows' then perform public.push_send(new.to_id, 'follow', new.from_id, null, null);
  elsif tg_table_name = 'freqs' then perform public.push_send(new.to_id, 'freq', new.from_id, null, null);
  elsif tg_table_name = 'dms' then perform public.push_send(new.to_id, 'dm', new.from_id, new.conv, case when new.text <> '' then new.text else '画像' end);
  elsif tg_table_name = 'announcements' then if new.to_id is not null then perform public.push_send(new.to_id, 'notice', null, new.id, new.text); end if;
  elsif tg_table_name = 'posts' then
    pub := public.is_public_post(new.author, new.aud);
    if new.reply_to is not null then
      select author into p from public.posts where id = new.reply_to;
      if found then perform public.push_send(p.author, 'reply', new.author, new.id, case when pub then new.text end); end if;
    end if;
    if new.quote_of is not null then
      select author into p from public.posts where id = new.quote_of;
      if found then perform public.push_send(p.author, 'quote', new.author, new.id, case when pub then new.text end); end if;
    end if;
    for h in select distinct lower(m[1]) from regexp_matches(new.text, '@([A-Za-z0-9_]{3,20})', 'g') m limit 10 loop
      select id into p from public.profiles where lower(handle) = h;
      if found and (pub or public.follows_(p.id, new.author)) then perform public.push_send(p.id, 'mention', new.author, new.id, case when pub then new.text end); end if;
    end loop;
  end if;
  return null;
exception when others then raise warning 'プッシュ通知の準備でエラー: %', sqlerrm; return null;
end $$;
do $$ declare t text; begin
  foreach t in array array['likes', 'reposts', 'follows', 'freqs', 'dms', 'posts', 'announcements'] loop
    execute format('drop trigger if exists push_notify on public.%I', t);
    execute format('create trigger push_notify after insert on public.%I for each row execute function public.push_on_change()', t);
  end loop;
end $$;
-- pg_net（データベースからWebへ通知を送る拡張機能）を有効にする
do $$ begin create extension if not exists pg_net;
exception when others then raise notice 'pg_net を有効にできませんでした（Database → Extensions で pg_net を有効にしてください）: %', sqlerrm; end $$;

-- ---------- 画面（ログインした人）がテーブルと関数を使えるようにする ----------
-- （新しい Supabase プロジェクトは自動では許可しないため。実際に読み書きできる範囲は下の RLS で制限します）
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- ---------- 読み書きの権限（Row Level Security） ----------
do $$ declare t text; begin
  foreach t in array array['profiles','admins','posts','likes','reposts','follows','freqs','blocks','private_docs','reports','report_status','hidden','suspended','announcements','modlog','dms','votes','communities','members','scheduled','badges','site_settings','push_subs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "read" on public.%I', t);
    execute format('drop policy if exists "insert" on public.%I', t);
    execute format('drop policy if exists "update" on public.%I', t);
    execute format('drop policy if exists "delete" on public.%I', t);
  end loop;
end $$;

create policy "read" on public.badges for select to authenticated using (true);
create policy "insert" on public.badges for insert to authenticated with check (public.is_admin());
create policy "update" on public.badges for update to authenticated using (public.is_admin());
create policy "delete" on public.badges for delete to authenticated using (public.is_admin());
create policy "read" on public.site_settings for select to authenticated using (true);
create policy "insert" on public.site_settings for insert to authenticated with check (public.is_admin());
create policy "update" on public.site_settings for update to authenticated using (public.is_admin());
create policy "delete" on public.site_settings for delete to authenticated using (public.is_admin());
create policy "read" on public.push_subs for select to authenticated using (uid = auth.uid());
create policy "insert" on public.push_subs for insert to authenticated with check (uid = auth.uid());
create policy "update" on public.push_subs for update to authenticated using (uid = auth.uid());
create policy "delete" on public.push_subs for delete to authenticated using (uid = auth.uid());
create policy "read" on public.profiles for select to authenticated using (true);
create policy "update" on public.profiles for update to authenticated using (id = auth.uid() or public.is_admin());

create policy "read" on public.admins for select to authenticated using (true);

create policy "read" on public.posts for select to authenticated using (public.can_see(author, aud, id));
create policy "insert" on public.posts for insert to authenticated with check (true);
create policy "update" on public.posts for update to authenticated using (author = auth.uid() or public.is_admin());
create policy "delete" on public.posts for delete to authenticated using (author = auth.uid() or public.is_admin() or (comm is not null and exists (select 1 from public.communities c where c.id = comm and c.owner = auth.uid())));

create policy "read" on public.likes for select to authenticated using (true);
create policy "insert" on public.likes for insert to authenticated with check (true);
create policy "delete" on public.likes for delete to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "read" on public.reposts for select to authenticated using (true);
create policy "insert" on public.reposts for insert to authenticated with check (true);
create policy "delete" on public.reposts for delete to authenticated using (user_id = auth.uid() or public.is_admin());

create policy "read" on public.follows for select to authenticated using (true);
create policy "insert" on public.follows for insert to authenticated with check (true);
create policy "delete" on public.follows for delete to authenticated using (from_id = auth.uid() or to_id = auth.uid() or public.is_admin());

create policy "read" on public.freqs for select to authenticated using (from_id = auth.uid() or to_id = auth.uid());

create policy "read" on public.blocks for select to authenticated using (true);
create policy "insert" on public.blocks for insert to authenticated with check (id = auth.uid());
create policy "update" on public.blocks for update to authenticated using (id = auth.uid());
create policy "delete" on public.blocks for delete to authenticated using (id = auth.uid());

create policy "read" on public.private_docs for select to authenticated using (uid = auth.uid());
create policy "insert" on public.private_docs for insert to authenticated with check (uid = auth.uid());
create policy "update" on public.private_docs for update to authenticated using (uid = auth.uid());
create policy "delete" on public.private_docs for delete to authenticated using (uid = auth.uid());

create policy "read" on public.reports for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "insert" on public.reports for insert to authenticated with check (true);
create policy "update" on public.reports for update to authenticated using (id = auth.uid());

do $$ declare t text; begin
  foreach t in array array['report_status', 'modlog'] loop
    execute format('create policy "read" on public.%I for select to authenticated using (public.is_admin())', t);
  end loop;
  foreach t in array array['hidden', 'suspended'] loop
    execute format('create policy "read" on public.%I for select to authenticated using (true)', t);
  end loop;
  foreach t in array array['report_status', 'modlog', 'hidden', 'suspended', 'announcements'] loop
    execute format('create policy "insert" on public.%I for insert to authenticated with check (public.is_admin())', t);
    execute format('create policy "update" on public.%I for update to authenticated using (public.is_admin())', t);
    execute format('create policy "delete" on public.%I for delete to authenticated using (public.is_admin())', t);
  end loop;
end $$;
create policy "read" on public.announcements for select to authenticated using (to_id is null or to_id = auth.uid() or public.is_admin());

create policy "read" on public.dms for select to authenticated using (from_id = auth.uid() or to_id = auth.uid());
create policy "read" on public.communities for select to authenticated using (true);
create policy "read" on public.members for select to authenticated using (true);
create policy "read" on public.scheduled for select to authenticated using (author = auth.uid());
create policy "delete" on public.scheduled for delete to authenticated using (author = auth.uid());
-- votes は直接は読めません（だれが何に投票したかは非公開）。集計は poll_results() で取得します。

-- ---------- 画面から呼ぶ処理（RPC） ----------
create or replace function public.me() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.need_strong();
  return jsonb_build_object('uid', auth.uid(), 'role', case when public.is_admin() then 'admin' else 'user' end,
    'email', (select email from auth.users where id = auth.uid()), 'handle', (select handle from public.profiles where id = auth.uid()),
    'suspended', public.is_susp(auth.uid()));
end $$;

create or replace function public.handle_available(h text) returns boolean language sql stable security definer set search_path = public as $$
  select h ~ '^[A-Za-z0-9_]{3,20}$' and not exists (select 1 from public.profiles where lower(handle) = lower(h))
$$;

create or replace function public.poll_results() returns table (post text, counts int[], mine int) language sql stable security definer set search_path = public as $$
  select v.post, array[count(*) filter (where choice = 0), count(*) filter (where choice = 1), count(*) filter (where choice = 2), count(*) filter (where choice = 3)]::int[],
    coalesce(max(case when v.user_id = auth.uid() then v.choice end), -1)
  from public.votes v join public.posts p on p.id = v.post
  where public.can_see(p.author, p.aud, p.id) and public.strong_session()
  group by v.post
$$;

create or replace function public.vote(post_id text, choice int) returns void language plpgsql security definer set search_path = public as $$
declare p record; me uuid := auth.uid();
begin
  perform public.need_strong();
  perform public.need_open();
  select * into p from public.posts where id = post_id;
  if not found or p.poll is null then perform public.fail('投票が見つかりません'); end if;
  if not public.can_see(p.author, p.aud, p.id) or public.blocked(p.author, me) then perform public.fail('この投票には参加できません'); end if;
  if public.is_susp(me) then perform public.fail('アカウントが凍結中です'); end if;
  if public.now_ms() > (p.poll->>'ends')::bigint then perform public.fail('この投票は締め切られました'); end if;
  if choice < 0 or choice >= jsonb_array_length(p.poll->'opts') then perform public.fail('入力内容を確認してください'); end if;
  if exists (select 1 from public.votes v where v.post = post_id and v.user_id = me) then perform public.fail('すでに投票しています'); end if;
  insert into public.votes (post, user_id, choice) values (post_id, me, choice);
  perform pg_notify('orbit', 'votes');
end $$;

create or replace function public.follow_req(target uuid) returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  perform public.need_strong();
  perform public.need_open();
  if target = me or not exists (select 1 from public.profiles where id = target) then perform public.fail('ユーザーが見つかりません'); end if;
  if public.is_susp(me) then perform public.fail('アカウントが凍結中です'); end if;
  if public.blocked(target, me) or public.blocked(me, target) then perform public.fail('このユーザーはフォローできません'); end if;
  if (select count(*) from public.freqs where from_id = me and at > public.now_ms() - 600000) >= 30 then perform public.fail('短時間に多くのリクエストは送れません'); end if;
  if public.is_locked(target) then
    insert into public.freqs (id, from_id, to_id) values (me::text || '__' || target::text, me, target) on conflict do nothing;
  else
    perform set_config('orbit.approving', 'on', true);
    insert into public.follows (id, from_id, to_id) values (me::text || '__' || target::text, me, target) on conflict do nothing;
    perform set_config('orbit.approving', 'off', true);
  end if;
end $$;

create or replace function public.freq_answer(requester uuid, ok boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if not exists (select 1 from public.freqs where from_id = requester and to_id = auth.uid()) then return; end if;
  if ok then
    perform set_config('orbit.approving', 'on', true);
    insert into public.follows (id, from_id, to_id) values (requester::text || '__' || auth.uid()::text, requester, auth.uid()) on conflict do nothing;
    perform set_config('orbit.approving', 'off', true);
  end if;
  delete from public.freqs where from_id = requester and to_id = auth.uid();
end $$;

create or replace function public.freq_cancel(target uuid) returns void language sql security definer set search_path = public as $$
  delete from public.freqs where from_id = auth.uid() and to_id = target and public.strong_session()
$$;

drop function if exists public.dm_send(uuid, text, jsonb);
create or replace function public.dm_send(target uuid, body text, media jsonb default '[]', reply text default null) returns text language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cv text; pref text; nid text;
begin
  perform public.need_strong();
  perform public.need_open();
  body := btrim(coalesce(body, ''));
  if char_length(body) > 1000 then perform public.fail('メッセージは1000文字以内で入力してください'); end if;
  if media is null or jsonb_typeof(media) <> 'array' then media := '[]'; end if;
  media := (select coalesce(jsonb_agg(jsonb_build_object('id', m->>'id', 'type', case when m->>'type' = 'video' then 'video' else 'image' end, 'alt', left(coalesce(m->>'alt', ''), 400))), '[]')
            from (select m from jsonb_array_elements(media) m where m->>'id' like me::text || '/%' limit 1) t);
  if body = '' and jsonb_array_length(media) = 0 then perform public.fail('メッセージを入力してください'); end if;
  if body <> '' and public.ng_hit(body) and not public.is_admin() then perform public.fail('禁止されている語句が含まれています'); end if;
  if target = me then perform public.fail('自分にはメッセージを送れません'); end if;
  if not exists (select 1 from public.profiles where id = target) then perform public.fail('ユーザーが見つかりません'); end if;
  if public.is_susp(me) and not public.is_admin() then perform public.fail('アカウントが凍結中のためメッセージを送れません'); end if;
  if public.blocked(target, me) or public.blocked(me, target) then perform public.fail('このユーザーにはメッセージを送れません'); end if;
  cv := case when me::text < target::text then me::text || '__' || target::text else target::text || '__' || me::text end;
  if not exists (select 1 from public.dms where conv = cv and from_id = target) then
    select coalesce(json->>'dm', 'all') into pref from public.private_docs where uid = target and key = 'state';
    if coalesce(pref, 'all') = 'none' then perform public.fail('このユーザーはメッセージを受け付けていません'); end if;
    if pref = 'following' and not public.follows_(target, me) then perform public.fail('このユーザーは、フォローしている人からのメッセージだけを受け付けています'); end if;
  end if;
  if (select count(*) from public.dms where from_id = me and at > public.now_ms() - 60000) >= 20 then perform public.fail('メッセージの送信が多すぎます。少し待ってください'); end if;
  if reply is not null and not exists (select 1 from public.dms where id = reply and conv = cv) then reply := null; end if;
  nid := 'm' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 14);
  insert into public.dms (id, conv, from_id, to_id, text, media, reply_to) values (nid, cv, me, target, body, media, reply);
  return nid;
end $$;

-- 自分のメッセージを編集
create or replace function public.dm_edit(mid text, body text) returns void language plpgsql security definer set search_path = public as $$
declare m record;
begin
  perform public.need_strong();
  perform public.need_open();
  select * into m from public.dms where id = mid;
  if not found then perform public.fail('メッセージが見つかりません'); end if;
  if m.from_id <> auth.uid() then perform public.fail('自分のメッセージだけ編集できます'); end if;
  body := btrim(coalesce(body, ''));
  if char_length(body) > 1000 then perform public.fail('メッセージは1000文字以内で入力してください'); end if;
  if body = '' and jsonb_array_length(m.media) = 0 then perform public.fail('メッセージを入力してください'); end if;
  if body <> '' and public.ng_hit(body) and not public.is_admin() then perform public.fail('禁止されている語句が含まれています'); end if;
  if body = m.text then return; end if;
  update public.dms set text = body, edited_at = public.now_ms() where id = mid;
end $$;

create or replace function public.dm_read(cv text) returns void language sql security definer set search_path = public as $$
  update public.dms set read_at = public.now_ms() where conv = cv and to_id = auth.uid() and read_at = 0 and public.strong_session()
$$;

create or replace function public.dm_react(mid text, emoji text) returns void language plpgsql security definer set search_path = public as $$
declare m record; lst jsonb; me text := auth.uid()::text;
begin
  perform public.need_strong();
  perform public.need_open();
  if emoji not in ('❤️', '😂', '😮', '😢', '👍', '🔥', '🎉', '🙏') then perform public.fail('このリアクションは使えません'); end if;
  select * into m from public.dms where id = mid for update;
  if not found then perform public.fail('メッセージが見つかりません'); end if;
  if m.from_id <> auth.uid() and m.to_id <> auth.uid() then perform public.fail('この操作は許可されていません'); end if;
  if public.blocked(m.from_id, m.to_id) or public.blocked(m.to_id, m.from_id) then perform public.fail('このユーザーとはやり取りできません'); end if;
  lst := coalesce(m.reacts->emoji, '[]');
  if lst ? me then lst := lst - me; else lst := lst || to_jsonb(me); end if;
  update public.dms set reacts = case when jsonb_array_length(lst) = 0 then reacts - emoji else jsonb_set(reacts, array[emoji], lst) end where id = mid;
end $$;

create or replace function public.dm_delete(mid text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if exists (select 1 from public.dms where id = mid and from_id <> auth.uid()) then perform public.fail('自分のメッセージだけ削除できます'); end if;
  delete from public.dms where id = mid and from_id = auth.uid();
end $$;

create or replace function public.set_nsfw(post_id text, on_ boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if not exists (select 1 from public.posts where id = post_id and (author = auth.uid() or public.is_admin())) then perform public.fail('この操作は許可されていません'); end if;
  update public.posts set nsfw = on_ where id = post_id;
end $$;

create or replace function public.comm_create(c_name text, c_desc text, c_color text) returns text language plpgsql security definer set search_path = public as $$
declare nid text; me uuid := auth.uid();
begin
  perform public.need_strong();
  perform public.need_open();
  c_name := left(btrim(coalesce(c_name, '')), 40);
  if c_name = '' then perform public.fail('コミュニティ名を入力してください'); end if;
  if public.ng_hit(c_name || ' ' || coalesce(c_desc, '')) and not public.is_admin() then perform public.fail('禁止されている語句が含まれています'); end if;
  if public.is_susp(me) then perform public.fail('アカウントが凍結中です'); end if;
  if (select count(*) from public.communities where owner = me) >= 5 then perform public.fail('作成できるコミュニティは5つまでです'); end if;
  if exists (select 1 from public.communities where lower(name) = lower(c_name)) then perform public.fail('同じ名前のコミュニティがあります'); end if;
  nid := 'c' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  insert into public.communities (id, name, descr, owner, color) values (nid, c_name, left(btrim(coalesce(c_desc, '')), 300), me, case when c_color ~ '^#[0-9a-fA-F]{6}$' then c_color else '' end);
  insert into public.members (id, comm, user_id, role) values (nid || '__' || me::text, nid, me, 'owner');
  return nid;
end $$;

create or replace function public.comm_update(c_id text, c_name text, c_desc text, c_color text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if not exists (select 1 from public.communities where id = c_id and (owner = auth.uid() or public.is_admin())) then perform public.fail('この操作は許可されていません'); end if;
  if btrim(coalesce(c_name, '')) = '' then perform public.fail('コミュニティ名を入力してください'); end if;
  update public.communities set name = left(btrim(c_name), 40), descr = left(btrim(coalesce(c_desc, '')), 300), color = case when c_color ~ '^#[0-9a-fA-F]{6}$' then c_color else color end where id = c_id;
end $$;

create or replace function public.comm_join(c_id text) returns void language plpgsql security definer set search_path = public as $$
declare c record;
begin
  perform public.need_strong();
  perform public.need_open();
  select * into c from public.communities where id = c_id;
  if not found then perform public.fail('コミュニティが見つかりません'); end if;
  if public.is_susp(auth.uid()) then perform public.fail('アカウントが凍結中です'); end if;
  if public.blocked(c.owner, auth.uid()) then perform public.fail('このコミュニティには参加できません'); end if;
  insert into public.members (id, comm, user_id) values (c_id || '__' || auth.uid()::text, c_id, auth.uid()) on conflict do nothing;
end $$;

create or replace function public.comm_leave(c_id text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if exists (select 1 from public.communities where id = c_id and owner = auth.uid()) then perform public.fail('作成者は退出できません。コミュニティを削除してください'); end if;
  delete from public.members where comm = c_id and user_id = auth.uid();
end $$;

create or replace function public.comm_kick(c_id text, target uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if not exists (select 1 from public.communities where id = c_id and (owner = auth.uid() or public.is_admin())) then perform public.fail('この操作は許可されていません'); end if;
  if exists (select 1 from public.communities where id = c_id and owner = target) then perform public.fail('作成者は外せません'); end if;
  delete from public.members where comm = c_id and user_id = target;
end $$;

create or replace function public.comm_delete(c_id text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  perform public.need_open();
  if not exists (select 1 from public.communities where id = c_id and (owner = auth.uid() or public.is_admin())) then perform public.fail('この操作は許可されていません'); end if;
  delete from public.posts where comm = c_id;
  delete from public.communities where id = c_id;
end $$;

-- 予約投稿
create or replace function public.schedule_post(post jsonb, at_ms bigint) returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  perform public.need_strong();
  perform public.need_open();
  if at_ms <= public.now_ms() + 60000 then perform public.fail('予約日時は1分以上先にしてください'); end if;
  if at_ms > public.now_ms() + 60::bigint * 86400000 then perform public.fail('予約できるのは60日先までです'); end if;
  if public.is_susp(me) then perform public.fail('アカウントが凍結中のため投稿できません'); end if;
  if (select count(*) from public.scheduled where author = me) >= 50 then perform public.fail('予約できる投稿は50件までです'); end if;
  if char_length(coalesce(post->>'text', '')) > 280 then perform public.fail('280文字以内で入力してください'); end if;
  insert into public.scheduled (id, author, json, at) values ('s' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 14), me, post, at_ms);
end $$;

create or replace function public.publish_due() returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  perform set_config('orbit.sched', 'on', true);
  for r in select * from public.scheduled where at <= public.now_ms() order by at for update skip locked loop
    begin
      perform set_config('request.jwt.claim.sub', r.author::text, true);
      perform set_config('request.jwt.claims', jsonb_build_object('sub', r.author::text, 'role', 'authenticated')::text, true);
      insert into public.posts (id, author, text, media, poll, aud, scope, nsfw, comm, quote_of)
      values ('p' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 14), r.author, coalesce(r.json->>'text', ''), coalesce(r.json->'media', '[]'),
        r.json->'poll', coalesce(r.json->>'aud', 'all'), coalesce(r.json->>'scope', 'all'), coalesce((r.json->>'nsfw')::boolean, false), nullif(r.json->>'comm', ''), nullif(r.json->>'quoteOf', ''));
      n := n + 1;
    exception when others then raise notice '予約投稿 % を投稿できませんでした: %', r.id, sqlerrm;
    end;
    delete from public.scheduled where id = r.id;
  end loop;
  return n;
end $$;

-- オンライン状態（2分以内に通信があればオンライン）
create or replace function public.presence_sync(pref text) returns jsonb language plpgsql security definer set search_path = public as $$
declare out jsonb := '{}'; r record; now_ bigint := public.now_ms();
begin
  perform public.need_strong();
  if pref not in ('auto', 'busy', 'offline') then pref := 'auto'; end if;
  update public.profiles set last_seen = now_, presence = pref where id = auth.uid();
  for r in select id, last_seen, presence from public.profiles where last_seen > now_ - 30::bigint * 86400000 loop
    if r.id = auth.uid() then out := out || jsonb_build_object(r.id::text, jsonb_build_object('s', case pref when 'offline' then 'offline' when 'busy' then 'busy' else 'online' end, 'self', pref));
    elsif r.presence = 'offline' then out := out || jsonb_build_object(r.id::text, jsonb_build_object('s', 'offline'));
    elsif now_ - r.last_seen < 120000 then out := out || jsonb_build_object(r.id::text, jsonb_build_object('s', case when r.presence = 'busy' then 'busy' else 'online' end));
    else out := out || jsonb_build_object(r.id::text, jsonb_build_object('s', 'offline', 'at', r.last_seen));
    end if;
  end loop;
  return out;
end $$;

create or replace function public.admin_info() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.need_strong();
  if not public.is_admin() then perform public.fail('この操作は許可されていません'); end if;
  return jsonb_build_object('pending', (select count(*) from public.scheduled), 'backup', true, 'lastBackup', 0,
    'sched', exists (select 1 from pg_extension where extname = 'pg_cron'));
end $$;

-- アカウント削除（本人のみ）
create or replace function public.delete_account() returns void language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid();
begin
  perform public.need_strong();
  if me is null then perform public.fail('ログインしてください'); end if;
  if public.is_admin() and (select count(*) from public.admins) <= 1 and (select count(*) from public.profiles) > 1 then
    perform public.fail('最後の管理者は削除できません。先に他のユーザーを管理者にしてください（admins テーブルにユーザーIDを追加）');
  end if;
  delete from public.posts where comm in (select id from public.communities where owner = me);
  delete from auth.users where id = me;
end $$;

-- ---------- ログイン（メールアドレス or ユーザーID）と 2段階認証 ----------
-- 1) login_resolve: ID とパスワードが正しいときだけメールアドレスを返す（知らない人はメールアドレスを調べられない）
--    8回続けて失敗すると15分ロック
-- 2) メールのコード・リンクで入ったログインだけを「確認済み」として扱う
--    パスワードだけのログインは、30日以内にコードで確認した端末（trusted_devices）からのときだけ確認済みになる
drop function if exists public.login_email(text, text);
drop table if exists public.login_attempts;
create table if not exists public.login_guard (uid uuid primary key references auth.users(id) on delete cascade, fails int not null default 0, until bigint not null default 0);
create table if not exists public.trusted_devices (uid uuid not null references auth.users(id) on delete cascade, hash text not null, label text not null default '', created bigint not null default public.now_ms(), expires bigint not null, primary key (uid, hash));
alter table public.login_guard enable row level security;
alter table public.trusted_devices enable row level security;
alter table public.strong_sessions enable row level security;

create or replace function public.login_resolve(p_id text, p_pw text) returns jsonb language plpgsql security definer set search_path = public, extensions, auth as $$
declare u record; g record; now_ bigint := public.now_ms(); bad constant text := 'メールアドレス（またはユーザーID）かパスワードが違います';
begin
  p_id := regexp_replace(lower(btrim(coalesce(p_id, ''))), '^@+', '');
  if p_id = '' or coalesce(p_pw, '') = '' then return jsonb_build_object('ok', false, 'error', bad); end if;
  if position('@' in p_id) > 0 then
    select au.id, au.email, au.encrypted_password, au.email_confirmed_at into u from auth.users au where lower(au.email) = p_id limit 1;
  else
    select au.id, au.email, au.encrypted_password, au.email_confirmed_at into u from public.profiles p join auth.users au on au.id = p.id where lower(p.handle) = p_id limit 1;
  end if;
  if u.id is null then return jsonb_build_object('ok', false, 'error', bad); end if;
  select * into g from public.login_guard where uid = u.id;
  if found and g.until > now_ then
    return jsonb_build_object('ok', false, 'locked', true, 'error', 'ログインの失敗が続いたため、一時的にロックしています。15分ほど待ってからお試しください');
  end if;
  if coalesce(u.encrypted_password, '') = '' or u.encrypted_password <> crypt(p_pw, u.encrypted_password) then
    insert into public.login_guard as x (uid, fails, until) values (u.id, 1, 0)
    on conflict (uid) do update set
      fails = case when x.until > 0 and x.until <= now_ then 1 else x.fails + 1 end,
      until = case when (case when x.until > 0 and x.until <= now_ then 1 else x.fails + 1 end) >= 8 then now_ + 900000 else 0 end;
    return jsonb_build_object('ok', false, 'error', bad);
  end if;
  delete from public.login_guard where uid = u.id;
  return jsonb_build_object('ok', true, 'email', u.email, 'confirmed', u.email_confirmed_at is not null);
end $$;

-- パスワードでログインした直後に呼ぶ：信頼済みの端末なら、このログインを確認済みにする
create or replace function public.device_check(p_token text) returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare sid text := auth.jwt() ->> 'session_id';
begin
  if auth.uid() is null or sid is null or coalesce(p_token, '') = '' then return false; end if;
  if not exists (select 1 from public.trusted_devices where uid = auth.uid() and hash = encode(digest(p_token, 'sha256'), 'hex') and expires > public.now_ms()) then return false; end if;
  insert into public.strong_sessions (session_id, uid) values (sid, auth.uid()) on conflict do nothing;
  return true;
end $$;

-- 確認済みのログインのときに呼ぶ：この端末を30日間信頼する（延長はしない）
create or replace function public.device_trust(p_token text, p_label text) returns void language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  perform public.need_strong();
  if coalesce(length(p_token), 0) < 20 then return; end if;
  h := encode(digest(p_token, 'sha256'), 'hex');
  delete from public.trusted_devices where uid = auth.uid() and expires <= public.now_ms();
  delete from public.strong_sessions where at < public.now_ms() - 90::bigint * 86400000;
  insert into public.trusted_devices (uid, hash, label, expires) values (auth.uid(), h, left(coalesce(p_label, ''), 80), public.now_ms() + 30::bigint * 86400000)
  on conflict (uid, hash) do nothing;
end $$;

-- 信頼済みの端末をすべて解除（パスワード変更時などに使う）
create or replace function public.devices_forget() returns void language plpgsql security definer set search_path = public as $$
begin perform public.need_strong(); delete from public.trusted_devices where uid = auth.uid(); end $$;

-- 確認済みでないログインでは、どのデータも読み書きできないようにする
do $$ declare t text; begin
  foreach t in array array['profiles','admins','posts','likes','reposts','follows','freqs','blocks','private_docs','reports','report_status','hidden','suspended','announcements','modlog','dms','votes','communities','members','scheduled'] loop
    execute format('drop policy if exists "strong" on public.%I', t);
    execute format('create policy "strong" on public.%I as restrictive for all to authenticated using (public.strong_session()) with check (public.strong_session())', t);
  end loop;
  foreach t in array array['badges','site_settings','push_subs'] loop
    execute format('drop policy if exists "strong" on public.%I', t);
    execute format('create policy "strong" on public.%I as restrictive for all to authenticated using (public.strong_session()) with check (public.strong_session())', t);
  end loop;
  -- メンテナンス中は、管理者以外は書き込めない（閲覧のみ）
  foreach t in array array['profiles','posts','likes','reposts','follows','freqs','blocks','reports','communities','members','scheduled'] loop
    execute format('drop policy if exists "maint_ins" on public.%I', t);
    execute format('drop policy if exists "maint_upd" on public.%I', t);
    execute format('drop policy if exists "maint_del" on public.%I', t);
    execute format('create policy "maint_ins" on public.%I as restrictive for insert to authenticated with check (not public.maintenance() or public.is_admin())', t);
    execute format('create policy "maint_upd" on public.%I as restrictive for update to authenticated using (not public.maintenance() or public.is_admin())', t);
    execute format('create policy "maint_del" on public.%I as restrictive for delete to authenticated using (not public.maintenance() or public.is_admin())', t);
  end loop;
end $$;

-- RPCを呼べるのはログインした人だけ
do $$ declare f text; begin
  foreach f in array array['me()','handle_available(text)','poll_results()','vote(text,int)','follow_req(uuid)','freq_answer(uuid,boolean)','freq_cancel(uuid)',
    'dm_send(uuid,text,jsonb,text)','dm_edit(text,text)','dm_read(text)','dm_react(text,text)','dm_delete(text)','set_nsfw(text,boolean)','comm_create(text,text,text)','comm_update(text,text,text,text)',
    'comm_join(text)','comm_leave(text)','comm_kick(text,uuid)','comm_delete(text)','schedule_post(jsonb,bigint)','presence_sync(text)','admin_info()','delete_account()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  execute 'grant execute on function public.handle_available(text) to anon';
  execute 'grant execute on function public.login_resolve(text,text) to anon, authenticated';
  execute 'grant execute on function public.site_public() to anon, authenticated';
  execute 'revoke all on table public.push_config from anon, authenticated';
  execute 'revoke all on function public.device_check(text) from anon';
  execute 'revoke all on function public.device_trust(text,text) from anon';
  execute 'revoke all on function public.devices_forget() from anon';
  execute 'revoke all on function public.publish_due() from public, anon, authenticated';
end $$;

-- ---------- 画像・動画の保存場所（Storage） ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 20971520, array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime'])
on conflict (id) do update set public = true, file_size_limit = 20971520, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "orbit media read" on storage.objects;
drop policy if exists "orbit media upload" on storage.objects;
drop policy if exists "orbit media delete" on storage.objects;
create policy "orbit media read" on storage.objects for select using (bucket_id = 'media');
create policy "orbit media upload" on storage.objects for insert to authenticated with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text and public.strong_session());
create policy "orbit media delete" on storage.objects for delete to authenticated using (bucket_id = 'media' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()) and public.strong_session());

-- ---------- リアルタイム配信 ----------
do $$ declare t text; begin
  foreach t in array array['posts','likes','reposts','follows','freqs','profiles','blocks','hidden','suspended','announcements','dms','communities','members','reports','report_status','modlog','private_docs','badges','site_settings','admins'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; when undefined_object then raise notice 'supabase_realtime がありません';
    end;
  end loop;
end $$;

-- ---------- 予約投稿の自動実行（1分ごと） ----------
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'orbit-scheduled';
  perform cron.schedule('orbit-scheduled', '* * * * *', 'select public.publish_due()');
exception when others then raise notice '予約投稿の自動実行は設定できませんでした（Database → Extensions で pg_cron を有効にして、もう一度実行してください）: %', sqlerrm;
end $$;
