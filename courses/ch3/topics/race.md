假設 A、B 各自 open 同一個 log，沒有 O_APPEND。兩者都想在尾端加資料，但各自有獨立 offset。

A 先 seek 到 EOF，B 也 seek 到相同 EOF。B 寫完後檔案變長，A 的 offset 卻沒有自動更新，接下來的 write 就可能覆蓋 B。

下面是指定排程的教學模擬。單步觀察一個具體反例，比只記「有 race」更有用。