-- ============================================================
-- Supabase 网盘：建私有桶 + RLS 权限策略
-- 这个版本是【可反复执行】的，重复跑不会报 already exists
--
-- 用法：整段复制到 Supabase → 左侧 SQL Editor → New query → 粘贴 → Run
-- 成功标志：Success. No rows returned
-- 注意：不要复制 Markdown 代码块上下那两行三个反引号
-- ============================================================


-- ------------------------------------------------------------
-- 1) 建私有桶（已存在就跳过）
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('netdisk', 'netdisk', false)
on conflict (id) do nothing;


-- ------------------------------------------------------------
-- 2) 清掉旧策略，避免 "policy ... already exists"（42710）
-- ------------------------------------------------------------
drop policy if exists "netdisk_read_own"   on storage.objects;
drop policy if exists "netdisk_insert_own" on storage.objects;
drop policy if exists "netdisk_update_own" on storage.objects;
drop policy if exists "netdisk_delete_own" on storage.objects;


-- ------------------------------------------------------------
-- 3) 重建 4 条策略：每个登录用户只能读写自己 uid 目录下的文件
--    网页上传时会自动把路径写成 <你的uid>/xxx，所以不同账号天然隔离
-- ------------------------------------------------------------
create policy "netdisk_read_own"
on storage.objects for select to authenticated
using (
  bucket_id = 'netdisk'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "netdisk_insert_own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'netdisk'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "netdisk_update_own"
on storage.objects for update to authenticated
using (
  bucket_id = 'netdisk'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'netdisk'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "netdisk_delete_own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'netdisk'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);


-- ------------------------------------------------------------
-- 4) 自检：应该返回 1 个桶 + 4 条策略
-- ------------------------------------------------------------
select 'bucket'::text as kind, id::text as name, public::text as info
from storage.buckets
where id = 'netdisk'

union all

select 'policy'::text as kind, policyname::text as name, cmd::text as info
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname like 'netdisk%'

order by kind, name;
