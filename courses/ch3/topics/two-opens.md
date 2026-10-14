假設檔案內容為 `foobar`，0、1、2 已占用，所有呼叫成功，沒有其他 process 修改檔案。

先預測第二次 read 讀到什麼，再逐步看右方的 entry。圖中的 A、B 是 open-file entries，不是兩份檔案複本。