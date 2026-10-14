stdout 連到 terminal 時通常採行緩衝；連到普通檔案時通常採全緩衝，但模式可以被設定，不能把它當作絕對不變的規則。

`fflush(stdout)` 把 stdio 累積的輸出交給底層；它不是 `fsync()`。即使資料離開 stdio buffer，仍可能在 Kernel cache。

若要在程式執行中更換 stdout 的 fd 連結，應留意先前尚未 flush 的內容，否則之後 flush 的資料可能走到新的目的地。