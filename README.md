# Orbit（オービット）

夜空を巡るように、みんなの今がつながるSNSです。

- 画面（このリポジトリ）は **Vercel** で公開します
- データ・ログイン・画像の保存は **Supabase** が担当します
- ビルド作業は不要です。ファイルをそのまま公開するだけで動きます

```
index.html            画面のすべて（デザイン・機能・多言語）
config.js             Supabase の接続先（ここだけ自分の値に書き換える）
supabase/schema.sql   データベースの設定（Supabase に貼り付けて実行する）
manifest.webmanifest  スマホのホーム画面に追加したときの設定
icons/                アイコン画像
vercel.json           公開時の設定
```

---

## はじめての公開手順

### 1. データベースを作る（Supabase）

1. [Supabase](https://supabase.com/dashboard) で、プロジェクト（例：`orbit`、リージョン：Northeast Asia (Tokyo)）を開きます
2. 左のメニューの **SQL Editor** を開きます
3. このリポジトリの `supabase/schema.sql` を開いて **中身をすべてコピー**し、SQL Editor に貼り付けて **Run** を押します
   - 「Success. No rows returned」と出れば完了です
   - 「予約投稿の自動実行は設定できませんでした」と出た場合は、**Database → Extensions** で `pg_cron` を有効にして、もう一度 Run してください
   - 何度実行しても大丈夫です（データは消えません）

### 2. 接続先を設定する（config.js）

1. Supabase の **Project Settings → API**（または **Connect** ボタン）を開きます
2. **Project URL** と **anon public key** をコピーします
3. GitHub でこのリポジトリの `config.js` を開き、鉛筆マーク（Edit）を押して、2つの値を `''` の中に貼り付けて保存（Commit changes）します

```js
window.ORBIT_CONFIG = {
  SUPABASE_URL: 'https://xxxxxxxx.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi...',
};
```

> anon key は公開されても大丈夫な鍵です。**service_role key は絶対に貼らないでください。**

### 3. 公開する（Vercel）

1. [Vercel](https://vercel.com/new) に GitHub アカウントでログインします
2. **Import Git Repository** で `orbit` を選んで **Import**
3. 設定はそのまま（Framework Preset は「Other」）で **Deploy** を押します
4. 表示された URL（例：`https://orbit-xxxx.vercel.app`）が Orbit のアドレスです

以後、GitHub のファイルを更新すると、Vercel が自動で公開し直します。

### 4. ログインの設定（Supabase）

1. Supabase の **Authentication → URL Configuration** を開きます
2. **Site URL** に Vercel の URL（例：`https://orbit-xxxx.vercel.app`）を入れて保存します
3. **Redirect URLs** にも同じ URL を追加します

これで、確認メールやパスワード再設定メールのリンクから Orbit に戻ってこられます。

### 5. 最初のアカウントを作る

Orbit を開いて「新しくアカウントを作る」から登録します。
**最初に登録した人が自動的に管理者**になります。

---

## メールについて（大事）

- Supabase 標準のメール送信は **1時間に数通まで** しか送れません。テストには十分ですが、たくさんの人に使ってもらう前に、**Authentication → SMTP Settings（Emails）** で外部のメール送信サービス（Resend など）を設定してください
- 確認メールには最初、リンクだけが書かれています。メールに **6桁のコード** も載せたい場合は、**Authentication → Email Templates** の「Confirm signup」と「Reset Password」の本文に、次の1行を追加してください

```html
<p>確認コード: <b>{{ .Token }}</b></p>
```

- テスト中にメール確認を省きたいときは、**Authentication → Sign In / Providers → Email** の「Confirm email」をオフにすると、登録してすぐ使えます（本番ではオンに戻してください）

## ログインについて

- ログインは **メールアドレス + パスワード** です（ユーザーIDではログインできません。メールアドレスを他の人に知られないようにするためです）
- 「他の端末からログアウト」で、ほかの端末のログインをまとめて解除できます

## 管理者を増やす・変える

Supabase の **Table Editor → admins** に、管理者にしたい人のユーザーID（`profiles` テーブルの `id`）を追加します。

## バックアップ

Supabase が毎日自動でバックアップを作成しています（**Database → Backups**）。

---

## まだ準備中の機能

| 機能 | 状態 |
| --- | --- |
| リンクのプレビュー（URLのカード表示） | 準備中（Supabase Edge Function で対応予定） |
| 投稿・DMの翻訳ボタン | 使えます（Google の翻訳サービスを直接利用） |
| 韓国語・中国語の自動翻訳 | 主要な文言は手作業で翻訳済み。残りは初回表示時に自動翻訳 |
| 独自ドメイン | Vercel の **Settings → Domains** から追加できます |

## 困ったとき

- 画面の下に赤い「問題が発生しました」が出たら、その内容をそのまま伝えてください
- 「config.js に Supabase の Project URL と anon key が入っていません」と出たら、手順2を確認してください
- 何かを変えたあと表示が変わらないときは、ページを再読み込み（スマホは一度タブを閉じて開き直し）してください
