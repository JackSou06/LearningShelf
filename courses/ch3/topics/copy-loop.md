外層用 read 的正數回傳值作為這批資料的長度；讀到 EOF 才完成。內層維護 `done`，每次從 `buf + done` 繼續寫剩下的 bytes。

本頁處理 blocking fd、EINTR 與 short write。Nonblocking 的 EAGAIN 需要等待就緒等另外的策略，不適合無限忙等。

下面是可放進程式的函式。需要的 headers 與檢查方式都保留，不使用教材外部的 apue.h。