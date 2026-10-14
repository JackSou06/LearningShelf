把檔案想成一本共用的書：file size 是書的長度，current offset 是某個 open-file entry 裡的書籤。

兩次獨立 `open()` 可以建立兩個書籤，指向同一本書；`dup()` 則讓兩個 fd 使用同一個書籤。

改書籤的位置不代表改書的長度。讀到 EOF 時，通常只是書籤到達尾端，檔案內容沒有消失。