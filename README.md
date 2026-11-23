# 松果在哪裡 PineFinder

中央大學智慧失物招領平台。此專案是純靜態網站：GitHub Pages 提供 Vanilla JavaScript 前端，Supabase 提供 PostgreSQL 與照片 Storage，不需要 Python 後端或 Railway。

```text
Browser → GitHub Pages (frontend/)
        → Supabase REST API (PostgreSQL)
        → Supabase Storage (photos)
        → Supabase Edge Function → Azure AI Vision → Azure OpenAI
```

## 重要：目前是公開匿名展示版

前端只使用 Supabase **Publishable key**（舊版名稱 `anon` key），絕不能放 Secret／`service_role` key。資料表與 Storage 使用 anon role 的 RLS policies。任何網路使用者都可以讀取待認領物品、建立通報、上傳照片及領取物品；通報聯絡方式和公開 bucket 照片也能被任何人查看。請只用虛構資料與不含個資的測試照片。這個設定不適合正式開放全校或存放真實學生資料。

## 一次性 Supabase 設定

1. 在 Supabase 建立或選取專案。
2. 打開 SQL Editor，執行 [`supabase/setup.sql`](supabase/setup.sql)。此腳本會建立 `public.lost_items`、RLS policies、原子領取 RPC，並建立／設定公開 bucket `lost-items`。
3. 到 Project Settings → API Keys，複製專案 URL 及 **Publishable key**（`sb_publishable_...`；舊版 `anon` key 亦可）。不要複製 Secret／`service_role` key。
4. 編輯 [`frontend/config.js`](frontend/config.js)：

   ```js
   window.PINEFINDER_CONFIG = {
     supabaseUrl: "https://<project-ref>.supabase.co",
     supabaseKey: "sb_publishable_...",
     storageBucket: "lost-items",
   };
   ```

   Publishable key 本來就會出現在瀏覽器；安全性依靠正確的 RLS，不是把這個 key 當密碼。請勿在 `config.js` 放任何 Secret／`service_role` key。根目錄舊的 `.env` 不會被靜態前端讀取，且不會部署至 Pages，勿將它提交至 GitHub。

5. 確認 `frontend/config.js` 與 `frontend/index.html` 一起提交並推送。`supabase/setup.sql` 只需在 Supabase SQL Editor 執行，不會部署到 Pages。

## AI 物品特徵

通報時，AI 會分析最多三張照片，提供可編輯的物品描述、類別、顏色及選填特徵。若照片內容觸發安全阻擋，或各張照片辨識出的類別不同，頁面會提示使用者；照片在確認通報前不會上傳至公開 Storage。AI 判斷可能誤判或漏判，請使用者確認辨識結果。照片會交由外部 AI 服務處理，請勿上傳含個人資料的照片。

既有資料庫若尚未拆分其他特徵欄位，請依序在 Supabase SQL Editor 執行 [`supabase/migrations/20261119_split_item_features.sql`](supabase/migrations/20261119_split_item_features.sql) 與 [`supabase/migrations/20261119_enforce_three_single_features.sql`](supabase/migrations/20261119_enforce_three_single_features.sql)；新資料庫請使用 [`supabase/setup.sql`](supabase/setup.sql)。

## 本機預覽

可用 VS Code Live Server 開啟 `frontend/index.html`，或在專案根目錄執行靜態檔案伺服器：

```bash
python3 -m http.server 8000 --directory frontend
```

這裡的 Python 只提供本機靜態檔案預覽，不是應用後端。瀏覽器開啟 `http://localhost:8000`。需先在 `frontend/config.js` 填好 Supabase URL 與 Publishable key。

## GitHub Pages 部署

專案已包含 [`.github/workflows/pages.yml`](.github/workflows/pages.yml)，推送至 `main` 時會自動部署 `frontend/`：

1. 把專案推送至 GitHub 的 `main` branch。
2. GitHub repository → Settings → Pages → Build and deployment → Source 選 **GitHub Actions**。
3. Actions 頁籤確認 `Deploy GitHub Pages` 成功，從 workflow 的 deployment link 開啟網站。
4. 確認 Supabase 專案的 API 設定與 RLS policies 已套用，再測通報、照片上傳、搜尋和領取。

GitHub Pages 免費使用資格依 repository visibility 和 GitHub 方案而異；一般免費個人／組織方案需使用 public repository。若 repository 不能公開，先確認帳號方案是否支援 private repository Pages。公開 repository 內的 Publishable key 是預期行為；仍不可提交 Secret key、資料庫密碼或 `.env`。

## 功能與限制

- 清單、搜尋、建立通報和領取都由瀏覽器直接呼叫 Supabase REST/Storage API。
- 照片只接受 JPEG、PNG、WebP；每張上限 8 MiB，每筆最多 3 張。Storage bucket 是公開的。
- 通報標籤使用 Azure AI Vision + Azure OpenAI 產生；失主搜尋必須輸入至少 1 個字的文字描述。文字分數由瀏覽器端 2-gram 計算；可附參考照片，但目前僅加入固定示意分數，不會進行以圖搜圖。
- 領取透過 `claim_lost_item` RPC 原子更新狀態，避免同一筆資料重複領取，但匿名使用者仍可領取任何物品。
- 沒有校園登入、角色權限、通報者身分驗證、濫用防護或管理介面。
