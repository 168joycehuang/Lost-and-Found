# 松果在哪裡 PineFinder

中央大學智慧失物招領平台。此專案是純靜態網站：GitHub Pages 提供 Vanilla JavaScript 前端，Supabase 提供 PostgreSQL 與照片 Storage，不需要 Python 後端或 Railway。

```text
Browser → GitHub Pages (frontend/)
        → Supabase REST API (PostgreSQL)
        → Supabase Storage (photos)
        → Supabase Edge Functions → Azure AI Vision / Azure OpenAI
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

## 文字語意搜尋設定

搜尋會先將使用者描述送至 `embed-text` Edge Function，由 Azure OpenAI Embedding 產生 1536 維向量；通報資料也會以相同模型和相同欄位格式產生向量。Supabase 使用 `pgvector` 搜尋待認領物品，排序依序為標題完全符合、標題／類別／顏色／特徵文字命中、向量語意相似度。搜尋不會使用照片，也不再顯示未校準的相似度百分比。

既有 Supabase 專案請依序在 SQL Editor 執行 [`supabase/migrations/20261123_add_text_embeddings.sql`](supabase/migrations/20261123_add_text_embeddings.sql)、[`supabase/migrations/20261125_remove_subtitle.sql`](supabase/migrations/20261125_remove_subtitle.sql)、[`supabase/migrations/20261125_similarity_score_null.sql`](supabase/migrations/20261125_similarity_score_null.sql) 與 [`supabase/migrations/20261126_add_browser_owned_item_editing.sql`](supabase/migrations/20261126_add_browser_owned_item_editing.sql)；移除副標題的 migration 會將內容拆至空白的其他特徵欄位，若既有欄位空間不足會中止並要求先手動處理，以避免遺失資料。新資料庫則執行 `supabase/setup.sql`。編輯功能 migration 會通知 PostgREST 重新載入 schema；若 API 仍回報找不到新欄位，請在 SQL Editor 執行 `NOTIFY pgrst, 'reload schema';`，並稍候幾秒再重試。搜尋結果會顯示 cosine similarity 向量分數（小數），僅作排序參考，不代表命中機率；尚未建立向量的舊資料會顯示「尚無向量」。部署 Edge Functions 並設定 secrets：

```bash
supabase functions deploy embed-text
supabase functions deploy backfill-embeddings
supabase secrets set \
  ALLOWED_ORIGIN="https://YOUR-SITE-DOMAIN" \
  AZURE_OPENAI_ENDPOINT="https://YOUR-RESOURCE.openai.azure.com/openai/v1" \
  AZURE_OPENAI_KEY="YOUR-AZURE-KEY" \
  AZURE_OPENAI_EMBEDDING_DEPLOYMENT="YOUR-DEPLOYMENT-NAME"
supabase secrets set BACKFILL_SECRET="YOUR-LONG-RANDOM-SECRET"
```

`AZURE_OPENAI_ENDPOINT` 與 `AZURE_OPENAI_KEY` 是原有 AI 分析和 Embedding 共用的預設值。若 Embedding 使用另一個 Azure OpenAI Resource，請勿用新值覆蓋原有 secrets；改為另外設定 `AZURE_OPENAI_EMBEDDING_ENDPOINT` 和 `AZURE_OPENAI_EMBEDDING_KEY`。Embedding Functions 會優先使用這兩個專用值，未設定時才回退使用原本的共用值。Azure key 屬於 Resource，不是單一模型部署的專用 key；同一 Resource 中新增模型部署通常沿用同一組 endpoint/key，只需設定新的 `AZURE_OPENAI_EMBEDDING_DEPLOYMENT`。

## 我的上傳與編輯

首頁右上角的「我的上傳」會列出目前瀏覽器提交的通報。每筆新通報會產生一組隨機管理憑證，原始憑證只存在該瀏覽器的 `localStorage`；資料庫只保存 SHA-256 雜湊。讀取個人清單及編輯資料都須提供憑證，資料表仍不開放匿名直接更新。可編輯物品文字、特徵、地點、日期與聯絡方式；照片不可修改，已領取的資料也不可編輯。

這不是帳號登入：清除網站資料、換瀏覽器或換裝置後，管理憑證無法自動復原；上線前建立的舊資料沒有憑證，不會出現在「我的上傳」。同一瀏覽器的其他使用者若能操作該瀏覽器，也能使用其中保存的管理憑證。這項功能適合展示用途，不應用來保護真實個資。

Embedding 使用不同 Azure Resource 時，另外執行以下命令，不會覆蓋原本 AI 分析所用的 endpoint/key：

```bash
supabase secrets set \
  AZURE_OPENAI_EMBEDDING_ENDPOINT="https://YOUR-EMBEDDING-RESOURCE.openai.azure.com/openai/v1" \
  AZURE_OPENAI_EMBEDDING_KEY="YOUR-EMBEDDING-RESOURCE-KEY"
```

Embedding 部署必須輸出 1536 維向量；建議使用 `text-embedding-3-small`，並確認該模型已在 Azure 專案中部署。若現有 `AZURE_OPENAI_ENDPOINT` 指向 `/openai/v1/responses`，Function 會自動改用同一資源的 `/openai/v1/embeddings`。請勿把 Azure key 或回填密碼放入前端設定或提交到 Git。

部署完成後，舊資料需手動分批回填。每次最多處理 10 筆尚未有向量的待認領物品，重複呼叫直到 `hasMore` 為 `false`：

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/backfill-embeddings" \
  -H "apikey: <SUPABASE_PUBLISHABLE_KEY>" \
  -H "Authorization: Bearer <BACKFILL_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"limit":5}'
```

回填 Function 使用 Supabase 注入的伺服器端 Secret key（舊專案使用 `SUPABASE_SERVICE_ROLE_KEY`），只接受獨立的 `BACKFILL_SECRET`；請妥善保管該密碼。Embedding Function 目前仍是匿名公開呼叫，Origin 檢查不是防止非瀏覽器濫用的安全控制。此 Demo 上線前仍需加上可靠的驗證／限流與用量上限。

目前回傳最多 50 筆，尚未設定語意相似度最低門檻；請用人工標註的查詢／正確物品案例評估誤配後，再決定門檻與排序策略。更換 Embedding 模型或維度時，必須重新產生所有已儲存向量並同步調整資料庫欄位；資料量變大時再評估建立向量索引。

## AI 物品特徵

通報時，AI 會分析最多三張照片，提供可編輯的類別、顏色及其他特徵。若照片內容觸發安全阻擋，或各張照片辨識出的類別不同，頁面會提示使用者；照片在確認通報前不會上傳至公開 Storage。AI 判斷可能誤判或漏判，請使用者確認辨識結果。照片會交由外部 AI 服務處理，請勿上傳含個人資料的照片。

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
- 通報標籤使用 Azure AI Vision + Azure OpenAI 產生；失主搜尋必須輸入文字描述，透過 Azure OpenAI Embedding 與 Supabase `pgvector` 進行文字語意搜尋，並優先顯示完全符合的標題。不支援圖片檢索。
- 領取透過 `claim_lost_item` RPC 原子更新狀態，避免同一筆資料重複領取，但匿名使用者仍可領取任何物品。
- 沒有校園登入、角色權限、通報者身分驗證、濫用防護或管理介面。
