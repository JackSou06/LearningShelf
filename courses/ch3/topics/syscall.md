你寫的 `add()` 可以直接在 user mode 計算。`read()` 的 C 介面通常透過函式庫包裝，把 fd、buffer 位址和大小交給 Kernel。

Kernel 驗證參數與可存取範圍，依檔案或裝置的狀態提供資料。完成後把回傳值交回程式。

**Mode switch 不等於 context switch。** 進入 Kernel 是權限模式改變；是否切換到另一個 process，取決於阻塞、排程等情況。