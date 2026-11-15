# 松果在哪裡 PineFinder

中央大學智慧失物招領平台。像松鼠埋藏與找回松果一樣，讓遺失在中大校園的每件物品都能被溫暖找回。

---

## 功能

- **拾獲者**：兩步驟通報遺失物，AI 自動產生類別、顏色、材質等標籤
- **失主**：文字描述或上傳舊照片搜尋，依相似度排行顯示結果
- 手機優先介面，支援暗色模式與鍵盤操作

## 執行方式

不需要安裝任何套件，用瀏覽器直接開啟即可：

```bash
git clone https://github.com/your-username/lost-and-found.git
```

然後開啟 `frontend/松果在哪裡_PineFinder.html`，雙擊或拖入瀏覽器即可執行。

## 目前限制

這是原型階段，主要缺口：

- 資料只存在記憶體，重新整理後消失
- 無身分驗證，任何人都能領取任何物品
- AI 標籤與圖片相似度為示意，尚未串接真正的影像辨識

---

## Git 使用指南

### 基本操作

```bash
# 複製專案到本機
git clone https://github.com/your-username/lost-and-found.git
cd lost-and-found

# 查看目前狀態
git status

# 將修改加入暫存區
git add 檔案名稱        # 加入特定檔案
git add .              # 加入所有修改

# 建立 commit
git commit -m "說明這次做了什麼"

# 推送到遠端
git push
```

### Branch 策略

專案採用 `main` + `feature branch` 的開發流程：

```
main              ← 穩定版，永遠可以直接開啟展示
└── feature/xxx   ← 每個新功能一條 branch，完成後 merge 回 main
```

**開發新功能的流程：**

```bash
# 1. 從 main 建立新 branch
git checkout main
git pull
git checkout -b feature/功能名稱

# 2. 開發、commit
git add .
git commit -m "feat: 說明這次做了什麼"

# 3. 完成後 merge 回 main
git checkout main
git merge feature/功能名稱

# 4. 刪除已合併的 branch
git branch -d feature/功能名稱
```

### Branch 命名規則

| 前綴 | 用途 | 範例 |
|---|---|---|
| `feature/` | 新功能開發 | `feature/後端串接` |
| `feature/` | 新功能開發 | `feature/身分驗證` |
| `fix/` | 修復 bug | `fix/修正領取流程` |

### Commit 訊息格式

```
feat: 新增照片上傳功能
fix: 修正搜尋結果排序錯誤
docs: 更新 README
style: 調整首頁配色
refactor: 重構搜尋演算法
```
