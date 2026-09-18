# Privi

[简体中文](./README.md) · [English](./README.zh-CN.md) · [繁體中文（香港）](./README.zh-HK.md)

個人使用、完全在裝置上的 **Android 媒體保險庫**。將相片和影片從系統相簿隱藏，支援 **1–3 顆紅心**評分、收藏、播放清單，以及**圖案 / PIN + 生物識別**鎖。內置 **ExoPlayer 播放器**（基於 Android Media3，支援無縫連續播放）。只支援深色主題。只提供 APK 側載安裝，不使用雲端儲存、帳戶或分析服務。

**作者：** [kcng0](https://github.com/kcng0) · **授權條款：** [MIT](./LICENSE) · **支持：** [Buy Me a Coffee](https://buymeacoffee.com/kcng0)

這是一個個人專案；優先保持簡單，不做功能堆疊。

---

## 安裝（APK）

Privi 不發佈到 Google Play。從 GitHub Release 下載 APK 側載安裝：

1. 開啟最新的 **[Release](https://github.com/kcng0/privi/releases/latest)**。
2. 下載 `privi-<version>.apk`（可選下載 `SHA256SUMS` 校驗檔案）。
3. 在電腦上校驗檔案完整性：
   ```bash
   sha256sum -c SHA256SUMS
   ```
4. 如有提示，在手機上允許瀏覽器或檔案管理器安裝未知來源應用。
5. 開啟 APK 完成安裝。

每個 Release 包含：

| 檔案 | 用途 |
|------|------|
| `privi-<version>.apk` | 側載安裝包 |
| `SHA256SUMS` / `.sha256` / `CHECKSUMS.txt` | 完整性校驗 |
| **原始碼（zip / tar.gz）** | GitHub 根據 tag 自動附加 |

**系統要求：** Android 8.0+（API 26）。所有媒體數據完全保留在裝置本地。

> 官方 GitHub Release APK 使用**永久簽名密鑰**（各版本簽名一致）。首次安裝新簽名應用時，Google Play Protect 可能提示「未知應用」——點擊**仍然安裝**即可，建議保持有害應用檢測開啟。

### 熱更新

從 **v1.0.4** 起，更新完全由用戶手動控制。打開 **設定 → 檢查更新**，會先檢查 GitHub 最新穩定版 Release，再檢查當前版本對應的 Shorebird 熱更新通道。發現新版本 Release 時顯示確認對話框並跳轉到 GitHub Release 頁面；有簽名的 Dart 補丁時，Privi 在下載前會請求確認。自 **v1.0.5** 起，補丁下載成功後自動重啟使補丁立即生效。關於頁面可查看基礎版本號、構建號和已應用補丁編號。

Android 原生程式碼、插件、權限、內置資源和 Flutter 引擎相關的變更仍需安裝新 APK。網絡請求僅在用戶手動檢查更新時發生，保險庫媒體數據始終保留在本地。

---

## 功能

- **Visible | Invisible 雙首頁**：瀏覽系統相簿資料夾或私密保險庫
- **馬賽克/列表視圖獨立記憶**：每個首頁頁籤分別保存自己的佈局偏好
- **隱藏資料夾**：從系統相簿中移除媒體，磁碟檔案不丟失
- **一致高清封面**：隱藏前後使用同一張 768px 影片幀
- **穩定日期排序**：隱藏後資料夾仍保持原始拍攝時間順序
- **紅心評分（0–3）** + 收藏、相簿排序、拖拽手動整理
- **合集管理**：創建、重命名、整理成員、無損解散（不刪除媒體檔案）
- **內置 ExoPlayer 播放器**：基於 Android Media3 ExoPlayer 的原生影片播放，支援**無縫連續播放**（影片結束後自動切換到下一首），格式兼容性遠超系統 MediaPlayer
- **外部播放器支援**：可調用手機安裝的第三方播放器（如 VLC），並追蹤播放結果
- **圖案 / PIN + 生物識別**鎖，可選 `FLAG_SECURE`（禁止截圖錄屏）
- **全局路由恢復鎖**：覆蓋所有頁面和頁籤，僅追蹤中的外部媒體應用返回可臨時繞過
- **分享匯入**：支援通過系統分享 Intent 將圖片和影片匯入 Privi
- 完全離線，所有數據保存在裝置本地

### 關鍵詞

`android photo vault` · `hide photos from gallery` · `private gallery app` ·
`video vault` · `offline media locker` · `pattern lock gallery` ·
`biometric photo lock` · `sideload apk vault` · `flutter media vault` ·
`hide videos android` · `no cloud gallery` · `exoplayer video player`

GitHub 主題標籤：`flutter` `android` `photo-vault` `video-vault` `private-gallery`
`hide-photos` `biometric-lock` `privacy` `offline` `sideload` `apk` `exoplayer` `mit-license`

---

## 截圖

以下截圖來自當前 **Privi v1.0.25** Flutter UI，使用合成資料夾、相簿、合集和內置應用圖標生成。未使用任何個人媒體或真實裝置，展示的是實際發佈的深色主題及最新 Visible/Invisible/合集流程。

維護者無需 Android 裝置即可重新生成：
`flutter test tool/readme_screenshots_test.dart --update-goldens`

| Visible 馬賽克 | Visible 列表 | Invisible 馬賽克 |
|:--------------:|:------------:|:----------------:|
| <img src="assets/screenshots/01_visible_mosaic.png" width="200" alt="Visible 系統資料夾馬賽克視圖"> | <img src="assets/screenshots/02_visible_list.png" width="200" alt="Visible 系統資料夾列表視圖"> | <img src="assets/screenshots/03_invisible_mosaic.png" width="200" alt="Invisible 相簿和合集馬賽克視圖"> |

| Invisible 列表 | 合集馬賽克 | 合集列表 |
|:--------------:|:--------:|:------:|
| <img src="assets/screenshots/04_invisible_list.png" width="200" alt="Invisible 相簿和合集列表視圖"> | <img src="assets/screenshots/05_collection_mosaic.png" width="200" alt="合集成員馬賽克視圖"> | <img src="assets/screenshots/06_collection_list.png" width="200" alt="合集成員列表視圖"> |

| 合集管理 | 設定 | 鎖設定 |
|:--------:|:----:|:------:|
| <img src="assets/screenshots/07_collection_management.png" width="200" alt="合集成員管理選單"> | <img src="assets/screenshots/08_settings.png" width="200" alt="安全、顯示和播放設定"> | <img src="assets/screenshots/09_lock_setup.png" width="200" alt="圖案鎖設定頁面"> |

- **Visible 馬賽克/列表**：按頁籤隔離保存的首頁視圖切換
- **Invisible 馬賽克/列表**：保險庫相簿、評分、數量和合集
- **合集頁面**：成員馬賽克/列表視圖及增刪改查管理
- **設定/鎖**：安全、顯示、播放和首次圖案設定

---

## 開發

### 前置要求

| 工具 | 說明 |
|------|------|
| Flutter **3.44.6** | 推薦使用 FVM（`.fvmrc` 鎖定精確版本） |
| JDK 17+ | Android Gradle 構建所需 |
| Android SDK | platform **37**、build-tools、cmdline-tools，需接受 licenses |
| 裝置 / 模擬器 | Android 8.0+（API 26） |

> **注意：** 本專案已移除 iOS 支援，僅構建 Android 版本。

### Ubuntu / WSL2 一鍵設定

```bash
git clone https://github.com/kcng0/privi.git
cd privi

# 可選：安裝 Flutter、Android SDK 及 licenses
./scripts/install-toolchain.sh && source ~/.bashrc

# 生成原生腳手架、安裝依賴、執行程式碼生成
./scripts/bootstrap.sh

# 在已連接裝置上執行
make run
```

### 日常指令

```bash
make run       # 在已連接裝置上啟動
make test      # 單元測試 + widget 測試
make analyze   # 靜態分析
make format    # dart format lib test
make gen       # build_runner 程式碼生成（Drift + Riverpod）
make watch     # 程式碼生成 watch 模式
make apk       # 生成側載 Release APK
make help      # 列出所有 Make 目標
```

不使用 `make` 時，可使用 `fvm flutter …`（未安裝 FVM 則直接用 `flutter`）。

完整環境說明、故障排查和 CI 細節見 **[DEVELOPMENT.md](./DEVELOPMENT.md)**。

### 倉庫結構

```
├── lib/           # Dart 原始碼（按功能組織）
├── test/          # 單元測試和 widget 測試
├── android/       # Android 宿主工程
├── assets/        # 品牌 / 圖標 / 截圖
├── scripts/       # bootstrap + 工具鏈安裝器
├── .github/       # CI + Release 工作流
├── pubspec.yaml
├── Makefile
└── DEVELOPMENT.md
```

---

## Release 與 CI

| 工作流 | 觸發條件 | 內容 |
|--------|---------|------|
| [CI](./.github/workflows/ci.yaml) | push / PR 到 `main` | format、codegen、analyze、test |
| [Release](./.github/workflows/release.yml) | tag `v*` 或手動觸發 | Shorebird 基礎 APK、校驗和與 GitHub Release |
| [Patch](./.github/workflows/patch.yml) | 在 `main` 上手動觸發 | 現有基礎版本的簽名 Dart 補丁 |

從乾淨的 `main` 創建 Release：

```bash
# 修改 pubspec.yaml 版本號（例如 0.1.0+1 → 0.1.1+2），提交後執行：
git tag v0.1.1
git push origin v0.1.1
```

也可以通過 **Actions → Release APK → Run workflow** 手動觸發。僅包含 Dart 程式碼的修復無需新 APK，通過 PR 合併後執行 **Actions → Shorebird Patch**，指定準確的基礎版本即可（例如 `1.0.4+5`）。

---

## 支持

如果 Privi 對你有所幫助，歡迎支持開發：

**[Buy Me a Coffee](https://buymeacoffee.com/kcng0)**

## 社群

- **[Linux do](https://linux.do)**

## 授權條款

[MIT](./LICENSE) — Copyright (c) 2026 [kcng0](https://github.com/kcng0)