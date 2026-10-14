使用 O_APPEND 的普通檔案寫入，每次 write 都以當時的尾端作為寫入起點。這避免前頁「先 seek、稍後用舊位置 write」的問題。

它不代表多次 write 自動合成一筆交易，也不保證不會 short write。不同檔案系統、尤其某些網路檔案系統，還有實作限制。

以 O_RDWR | O_APPEND 開啟仍可以讀取；lseek 可移動讀取位置，但接下來 write 仍按 append 規則選尾端。