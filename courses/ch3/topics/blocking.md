以還有 writer、但目前沒有資料的 pipe 為例：blocking read 可以等待；nonblocking read 會以 -1 與 EAGAIN 表示此時無法讀取。它不是已經受理、稍後自動填好 buffer。

Asynchronous I/O 是提交與完成分開通知／查詢的介面。Synchronized I/O completion（例如 O_SYNC）則關心資料與 metadata 的完成條件。

投影片對「synchronization」採儲存資料移動的教學語境；請勿直接把 delayed write 等同 POSIX AIO，或把 nonblocking 當作持久化模式。