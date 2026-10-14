`O_WRONLY | O_CREAT`：不存在就建立，已存在時不因 O_CREAT 自動清空。

`O_WRONLY | O_CREAT | O_TRUNC`：建立或覆寫，既有普通檔案會截斷成長度 0。`creat(path, mode)` 相當於這個組合。

`O_WRONLY | O_CREAT | O_EXCL`：要求建立新檔，若已存在就失敗。存在檢查與建立結合，稍後用來處理 race。

以下討論限一般檔案與有效存取模式；不要依賴 O_RDONLY 搭配 O_TRUNC 的可攜行為。