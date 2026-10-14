`O_APPEND`：該次 write 的尾端定位與寫入。`pread/pwrite`：定位 I/O 不借用共享 current offset。`O_CREAT | O_EXCL`：不存在才建立。`dup2`：替換指定 descriptor 的操作。

兩次 write、先 read 再修改再 write、或整個資料庫交易，都不能自動套用單次 API 的保證。

也別把 atomic 理解成「任何錯誤都會把整份資料完整回滾」。I/O 仍有 partial success 與錯誤處理。