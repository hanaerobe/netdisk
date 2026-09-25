# Supabase 网盘（用户名 + 密码登录，不需要邮箱）

前端是静态页面（放 GitHub Pages），后端交给 **Supabase**：它提供账号系统和文件存储。**注册只需要用户名和密码，用户全程不需要接触邮箱**，每个人只能看到自己的文件。

## 和「GitHub 令牌版」的区别

| | GitHub 版 | **Supabase 版** |
| --- | --- | --- |
| 登录方式 | 输入 GitHub 令牌（PAT） | **用户名 + 密码，自助注册** |
| 多用户 | 要手动给每人发令牌 | **注册即用，自动隔离** |
| 隔离靠什么 | 仓库权限 | **数据库 RLS 策略强制** |
| 单文件上限 | 25 MB | **50 MB（可调）** |
| 免费容量 | 仓库 ~1 GB | **1 GB 存储 + 5 GB 流量** |
| 依赖 | 只用 GitHub | 多一个 Supabase 账号 |

---

## 一、注册并建项目

1. 打开 https://supabase.com → **Start your project** → 用 GitHub 账号登录（免邮箱验证，最快）
2. **New project**：
   - Name：`netdisk`
   - Database Password：设一个强密码，**记下来**（日常用不到，但别丢）
   - Region：选 **Southeast Asia (Singapore)** 离国内最近
   - Plan：**Free**
3. 点创建，等 1~2 分钟初始化完成

> 免费版限制：**2 个项目上限**、**1 GB 文件存储**、**5 GB 流量**、**闲置 1 周自动暂停**（去后台点一下就能唤醒，数据不丢）。

---

## 二、建存储桶

**推荐直接用 SQL 建**（第四步的脚本里已经包含建桶语句，跳过这里也行）。

手动建的话：左侧 **Storage** → **New bucket** → Name 填 **`netdisk`**（必须一模一样）→ **不要勾 Public** → Save。

---

## 三、关掉邮箱确认（必须）

**这一步现在是硬性要求**：网页用的是"用户名映射成内部账号"的方案，内部账号的邮箱是虚构的，收不到任何邮件。如果邮箱确认开着，**注册出来的账号会永远无法激活，谁也登录不了**。

1. 左侧 **Authentication** → **Sign In / Providers**（老版本叫 Providers）
2. 找到 **Email**，确认已启用
3. 把 **Confirm email**（确认邮箱）**关掉** → Save

验证方法：直接在网页上注册一个账号，能立刻进去就是对的；如果提示"无法直接登录"，就是这一步没生效。

---

## 四、关键一步：建桶 + 配置权限策略（RLS）

**不做这一步，上传会直接报 `Bucket not found` 或 `new row violates row-level security policy`。**

打开同目录下的 **`netdisk-rls.sql`**（记事本打开 → `Ctrl+A` → `Ctrl+C`），粘到 **SQL Editor** → **New query** → **Run**。

这个脚本是**可反复执行**的：桶已存在会自动跳过，策略先删后建，所以重复跑不会报 `policy ... already exists`（42710）。

> ⚠️ 复制时不要带上 Markdown 代码块的 ``` 三引号，否则报 `syntax error at or near "```"`。用 `.sql` 文件复制就没这个问题。
> 也**不要只选中一部分执行**（比如只选策略那段）—— 那样就会漏掉建桶，之后上传一直报 `Bucket not found`。

看到 **Success. No rows returned** 就成功了。

**最后一段是自检查询**，会返回一个表格，应该正好 **5 行**：

| kind | name | info |
| --- | --- | --- |
| bucket | netdisk | false |
| policy | netdisk_delete_own | DELETE |
| policy | netdisk_insert_own | INSERT |
| policy | netdisk_read_own | SELECT |
| policy | netdisk_update_own | UPDATE |

少一行就说明没跑全。

> **兜底**：如果这条 `insert into storage.buckets` 因为任何原因不生效，直接在左侧 **Storage** → **New bucket** → 名字填 `netdisk` → **不勾 Public** → Save 也行，效果完全一样。

脚本干了什么：

| 做什么 | 为什么 |
| --- | --- |
| 建私有桶 `netdisk` | 文件的实际存放位置 |
| 4 条策略（select / insert / update / delete） | 限制「只能读写自己 `uid/` 目录下的文件」 |

网页上传时会自动把路径写成 `<你的uid>/xxx`，所以不同账号天然隔离，**这个隔离是数据库强制的，不是前端藏起来的**。

> 想改成"所有人共用同一个空间"：把策略里的
> `(storage.foldername(name))[1] = (select auth.uid())::text`
> 全部删掉，只留 `bucket_id = 'netdisk'` 即可（但这样每个注册用户都能看到别人的文件）。

---

## 五、拿到连接信息

左下角 **Project Settings**（齿轮）→ **Data API**（老版本叫 **API**），复制：

- **Project URL** → 形如 `https://abcdefghijk.supabase.co`
- **公开密钥**，两种格式都可能碰到：
  - 新版：**`sb_publishable_...`**
  - 老版：**`anon` `public`** → 形如 `eyJhbGciOiJIUzI1NiIs...`

> ⚠️ **绝对不要**用 **`sb_secret_...`**（新版）或 **`service_role`**（老版）——那是超级管理员密钥，能绕过所有权限检查，放进网页等于把整个数据库交出去。

> 公开密钥是**设计上就公开**的，会写进网页里，这不是漏洞 —— 真正的门禁是第四步的 RLS 策略，没有账号密码拿不到任何文件。

---

## 六、部署网页

**方式 A：GitHub Pages（推荐）**

1. 新建公开仓库 `supabase-netdisk`（别勾初始化）
2. 上传 `index.html`（网页：Add file → Upload files；或命令行）：
   ```powershell
   cd D:\程序源码\supabase-netdisk
   git init -b main
   git add .
   git commit -m "add supabase netdisk"
   git remote add origin https://github.com/你的用户名/supabase-netdisk.git
   git push -u origin main
   ```
3. 仓库 **Settings → Pages** → Source 选 `Deploy from a branch` → `main` / `(root)` → Save
4. 等 1~2 分钟，访问 `https://你的用户名.github.io/supabase-netdisk/`

**方式 B：本地试**：直接双击 `index.html`。

---

## 七、填配置

配置直接写在 `index.html` 开头：

```js
var DEFAULT_CFG = {
  url: 'https://abcdefghijk.supabase.co',
  key: 'sb_publishable_...'
};
```

**页面里已经没有任何配置入口了**：普通访客只会看到「登录 / 注册」和网盘界面，看不到后端地址、密钥、存储结构这些信息。要换 Supabase 项目，就改这段然后重新提交。

---

## 八、登录方式是怎么实现的（重要）

Supabase Auth 的底层只认**邮箱**或**手机号**，没有"用户名"这个概念。所以这里用了一个通用做法：

```
用户输入「张三」 → UTF-8 字节转十六进制 → e5bca0e4b889
                → 内部邮箱 u_e5bca0e4b889@netdisk.local
                → 拿这个邮箱去注册 / 登录
```

用户全程只看到和使用用户名，内部邮箱是不可见的。

**为什么用十六进制编码而不是直接用用户名当邮箱？** 这样中文、空格、各种符号都能当用户名，而且编码是唯一的，不会撞号。

**普通用户名的登录凭据的实际样子：**

| 行为 | 说明 |
| --- | --- |
| 用户名 | 1~10 个汉字，或 1~30 个字母；**大小写不敏感**（`Tom` 和 `tom` 是同一个账号） |
| 用户名唯一 | 同一个用户名不能重复注册 |
| 密码 | 至少 6 位 |

### ⚠️ 这个方案的代价（必须知道）

1. **忘记密码无法自助找回**。没有真实邮箱，发不了重置链接。用户忘密码只能由你（管理员）进 Supabase 后台 → Authentication → Users → 找到该用户 → 手动改密码或删掉重建。
2. **Supabase 后台的用户列表里显示的是内部邮箱**（`u_74657374@netdisk.local`），不是用户名。要认出是谁，得展开该用户的 `user_metadata.username`。
3. 系统里不是"实名"的：用户名随便填，没有任何真实性验证。要真正实名得接手机号短信验证（Supabase 支持，但需要自己接短信服务商，收费）。

**如果你更在意账号可找回**：把 `index.html` 里的邮箱字段加回来用真实邮箱注册，其它部分完全不用改。

---

## 九、验证清单

- [ ] 打开网址 → 看到「登录 / 注册」
- [ ] 点【注册】→ 填用户名 + 密码 → **直接进网盘**（如果提示无法登录，说明第三步没关邮箱确认）
- [ ] 上传文件 → 进度条走完显示"完成"
- [ ] 下载 → 文件能打开且内容完整
- [ ] 新建文件夹 → 进去能上传
- [ ] 删除文件 → 列表消失
- [ ] **退出 → 换个用户名注册 → 看不到前一个账号的文件**（隔离是否生效的关键验证）
- [ ] 去 Supabase 后台 Storage → netdisk，能看到 `一串uid/` 的目录结构

---

## 十、报错对照表（以下都是实测过的真实返回）

| 报错 | 含义 / 解决 |
| --- | --- |
| `Bucket not found`（`NoSuchBucket`） | 桶没建。第四步的 SQL 没跑成功 |
| `new row violates row-level security policy` | RLS 策略没跑，或桶名写错。回 SQL Editor 重跑 |
| 上传 / 下载 403 | 四条策略没跑全，或者少了其中某一条 |
| `Invalid login credentials` | 用户名或密码不正确（用户名不存在时也返回这个，防止探测） |
| `User already registered` | 用户名已被占用，换一个或点【登录】 |
| `Password should be at least 6 characters.` | 密码至少 6 位 |
| `Object not found`（`NoSuchKey`） | 文件已被删掉，刷新一下列表 |
| `Email rate limit exceeded` | 说明第三步的邮箱确认没关，回后台关掉 |
| 网页一直转圈 | 项目被暂停了（闲置 1 周），去 supabase.com 打开项目点 Restore |
| 上传报文件过大 | 免费版单文件默认 50 MB，Storage → Settings 可调整 |

---

## 十一、文件说明

```
supabase-netdisk/
├── index.html       # 整个网盘（单文件，无需构建）
├── netdisk-rls.sql  # 建桶 + RLS 策略，全选复制到 SQL Editor 跑
└── README.md        # 本说明
```

技术要点：

- 前端用官方 `@supabase/supabase-js` v2（unpkg CDN 引入）
- 上传：走 Storage 的 REST 接口 + `XMLHttpRequest`，所以有**真实百分比进度条**
- 下载：`createSignedUrl(path, 60, {download})` 生成 60 秒有效期的**签名链接**，过期自动失效
- 列目录：`POST /storage/v1/object/list/{bucket}`；空文件夹用一个隐藏的 `.folderkeep` 占位文件表示（对象存储没有真正的空目录概念）
- 文件名转义：Supabase Storage 只接受一部分 ASCII 字符（**中文等非 ASCII**、`#`、`%`、`~`、`[`、`]`、`` ` ``、`{`、`}`、`|`、`<`、`>`、`\`、`"`、`^` 全部会被拒并报 `Invalid key`）。所以存进存储时把非法字节写成 `!hh`（UTF-8 字节的十六进制），显示和下载时再还原成原名。

  > 副作用：在 Supabase 后台的 Storage 里，中文文件名会显示成 `!e4!b8!ad!e6!96!87` 这种样子（因为那是存储里的真实键名），但**网页上和下载下来的都是正常中文名**。纯 ASCII 文件名不受影响，原样存储。
- 所有路径自动加 `<uid>/` 前缀，配合 RLS 实现账号隔离
