對普通檔案，未使用 O_APPEND 時，寫入從 current offset 開始，offset 增加實際寫入量。覆蓋檔案中間的內容，不一定增加 file size。

假設檔案是 `foobar`、offset=2，成功寫入 `XY` 後是 `foXYar`，offset=4、size=6。若從 offset=6 寫入兩個 bytes，size 才變成 8。

Disk full、配額、signal 等可能造成錯誤或部分寫入。單次 write 成功也不等於資料已經持久化。