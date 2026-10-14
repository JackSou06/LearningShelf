`SEEK_SET` 以開頭 0 為基準；`SEEK_CUR` 以目前 offset 為基準；`SEEK_END` 以目前 file size 為基準。

例如 size=10、offset=3，執行 `lseek(fd, -2, SEEK_END)`，新位置是 8。普通檔案的最終 offset 不能是負數，但位移參數可以是負數。

`lseek(fd, 0, SEEK_CUR)` 可查詢目前位置。失敗回傳 `(off_t)-1`；lseek 本身不讀寫檔案內容。