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

- **メールアドレス または ユーザーID** と パスワードでログインできます
- **2段階認証**：初めての端末からログインするときは、登録メールアドレスに届く **6桁のコード** を入力します。一度確認した端末は **30日間** コードなしでログインできます
  - パスワードだけでは（コードを入れない限り）データを一切読み書きできないよう、データベース側で守っています
  - パスワードを変更すると、ほかの端末の「信頼」はすべて解除されます
  - 8回続けてパスワードを間違えると、そのアカウントは15分ロックされます
- **複数アカウント**：左下の自分の欄（スマホは左上のアイコン）を押すと、アカウントの切り替え・追加（最大5つ）・ログアウトができます

### 2段階認証のメール設定（必須）

ログイン用のコードは、Supabase の **Authentication → Emails → Email Templates** の **「Magic Link」** テンプレートで送られます。件名と本文を次のようにしてください。

件名：

```
【Orbit】ログイン確認コード
```

本文：

```html
<div style="font-family:sans-serif;max-width:480px;margin:auto;padding:24px;color:#1a2240">
<h2 style="color:#2a62ff;margin:0 0 16px">ログインの確認</h2>
<p>Orbit へのログインを確認するため、次のコードを画面に入力してください。</p>
<p style="text-align:center">確認コード<br><b style="font-size:28px;letter-spacing:6px">{{ .Token }}</b></p>
<p style="color:#888;font-size:12px">このコードは10分間有効です。心当たりがない場合は、パスワードが知られている可能性があります。パスワードを変更してください。</p>
</div>
```

あわせて **Authentication → Sign In / Providers → Email** で、**Email OTP Expiration** を `600`（10分）、**Email OTP Length** を `6` にしてください。

## 流れ星（Orbit だけの機能）

ホームのいちばん上に並ぶ、24時間で消える「いま」のひとことです。

- ひとこと（100文字まで）と写真1枚、空の色（夜空・夜明け・夕焼け・オーロラ）を選んで流します
- 流せるのは1人1つだけ。新しく流すと前の流れ星は消えます
- アイコンのまわりの**軌道の弧**が残り時間を表し、消える時間が近づくほど短くなります
- 見た人は「✨ 願いをかける」やメッセージで反応できます。流した人は、見た人と願いをかけた人を確認できます
- 消えた流れ星は1時間ごとに自動で片付けられます（pg_cron が有効な場合）

## 表示回数

投稿が画面に表示されると、1人1回として数えます（自分の投稿は数えません）。投稿の右下と、投稿の詳細ページに表示されます。

## 管理者の機能

左のメニューの **管理** から使えます（管理者にだけ表示されます）。

- **統計**：ユーザー数・アクティブ数・投稿数など
- **通報**：通報の確認と対応状況の記録、投稿の非表示、ユーザーの凍結
- **投稿管理**：全投稿の検索・非表示・削除
- **ユーザー管理**：検索・絞り込み、メールアドレスや登録日・最終ログインの確認、管理者の追加／解除、**認証バッジ**（認証済み・公式）の付与、警告・凍結、ログインのロック解除、信頼済み端末の解除、プロフィールの初期化、投稿の一括削除、アカウント削除
- **コミュニティ**：一覧・作成者の変更・削除
- **お知らせ**：全員または特定の人へのお知らせ
- **サイト設定**：新規登録の受付オン／オフ、メンテナンスモード（管理者以外は閲覧のみ）、NGワード
- **操作履歴**：管理者の操作の記録

最初に登録した人が管理者です。ほかの人を管理者にするときは、ユーザー管理の「管理者にする」を押してください。

## ロボット対策（Cloudflare Turnstile）

スパム業者のプログラムによる大量登録を防ぎます。利用者にはほとんど何も表示されません。

1. [Cloudflare](https://dash.cloudflare.com/sign-up) に無料登録し、左メニューの **Turnstile** → **Add widget** を押します
2. Widget name：`Orbit`、Hostname：Orbit のアドレス（例：`orbit-omega-drab.vercel.app`）、Widget Mode：**Managed** にして作成します
3. 表示された **Site Key** を `config.js` の `TURNSTILE_SITE_KEY` に入れて保存し、Vercel に反映されるのを待ちます（1分ほど）
4. そのあとで、Supabase の **Authentication → Attack Protection** で **Enable CAPTCHA protection** をオンにし、Provider を **Turnstile**、**Secret Key** に Cloudflare の Secret Key を入れて保存します

> 必ず **3 → 4 の順番** で行ってください。先に 4 をすると、サイトキーの入っていない Orbit からはログインできなくなります。

## プッシュ通知

いいね・返信・メンション・フォロー・メッセージなどを、アプリを閉じていても通知します。

1. `supabase/schema.sql` を SQL Editor でもう一度実行します（通知の仕組みが追加されます）
   - 「pg_net を有効にできませんでした」と出たら、**Database → Extensions** で `pg_net` を有効にして、もう一度実行してください
2. Supabase の **Edge Functions → Deploy a new function → Via Editor** を開き、名前を `push` にして、`supabase/functions/push/index.ts` の中身をすべて貼り付けて **Deploy** します
3. 作った `push` 関数の設定（Details / Settings）で **Verify JWT（Enforce JWT verification）をオフ** にして保存します
4. Orbit の **設定 → プッシュ通知** で「オンにする」を押します

- iPhone・iPad は、Safari で Orbit を開き、共有ボタン →「ホーム画面に追加」で追加したアプリから設定してください（iOS 16.4 以降）
- 通知の種類ごとのオン／オフは、設定の「通知」から変えられます。ミュートしている人からの通知は届きません

## バックアップ

Supabase が毎日自動でバックアップを作成しています（**Database → Backups**）。

---

## まだ準備中の機能

| 機能 | 状態 |
| --- | --- |
| リンクのプレビュー（URLのカード表示） | 準備中（Supabase Edge Function で対応予定） |
| 表示テーマ | 設定から ダーク（夜空）／ライト／端末に合わせる を選べます |
| 投稿・DMの翻訳ボタン | 使えます（Google の翻訳サービスを直接利用） |
| 韓国語・中国語の自動翻訳 | 主要な文言は手作業で翻訳済み。残りは初回表示時に自動翻訳 |
| 独自ドメイン | Vercel の **Settings → Domains** から追加できます |

## 困ったとき

- 画面の下に赤い「問題が発生しました」が出たら、その内容をそのまま伝えてください
- 「config.js に Supabase の Project URL と anon key が入っていません」と出たら、手順2を確認してください
- 何かを変えたあと表示が変わらないときは、ページを再読み込み（スマホは一度タブを閉じて開き直し）してください
