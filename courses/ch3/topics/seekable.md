普通檔案通常支援 seek；pipe、FIFO、socket 通常不支援這種隨機定位。對它們呼叫 lseek 會失敗。

**教材校正：這類失敗是 ESPIPE，而不是 EPIPE。** 投影片第 32 頁的 EPIPE 不宜照抄。

`EPIPE` 常見於向沒有 reader 的 pipe 寫入，與本頁的 seek 失敗是不同問題。