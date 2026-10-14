`open()` 兩次：兩個 entry。`dup()`：增加指向同一 entry 的 fd。`fork()`：child 繼承指向原 entries 的 fd。

檔案內容被其中一方寫入後，其他開啟者可能看見內容變更；這不代表它們的 offset 就因此變成共享。**內容共享與位置共享必須分開判斷。**