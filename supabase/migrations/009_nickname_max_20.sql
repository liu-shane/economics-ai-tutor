begin;

-- 新輸入與後續修改的排行榜暱稱一律限制為 20 個字元。
-- NOT VALID 會保留任何既有的過長暱稱，不會自動截斷使用者資料。
alter table public.profiles
  add constraint profiles_nickname_max_20_check
  check (nickname is null or char_length(nickname) <= 20) not valid;

create or replace function public.update_my_leaderboard_profile(
  requested_nickname text,
  requested_public boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare clean_nickname text := nullif(trim(requested_nickname),'');
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if clean_nickname is not null and char_length(clean_nickname) not between 1 and 20 then
    raise exception 'INVALID_NICKNAME';
  end if;

  insert into public.profiles(user_id,nickname,leaderboard_public)
  values(auth.uid(),clean_nickname,coalesce(requested_public,true))
  on conflict(user_id) do update
  set nickname=excluded.nickname,
      leaderboard_public=excluded.leaderboard_public,
      updated_at=now();

  return jsonb_build_object(
    'nickname',clean_nickname,
    'public',coalesce(requested_public,true)
  );
end;
$$;

revoke all on function public.update_my_leaderboard_profile(text,boolean) from public;
grant execute on function public.update_my_leaderboard_profile(text,boolean) to authenticated;

commit;
