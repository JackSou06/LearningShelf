`O_RDONLY` 表示只讀，`O_WRONLY` 表示只寫，`O_RDWR` 表示讀寫。請直接選其中一種，再 OR 上其他開啟選項。

在常見實作中 `O_RDONLY` 的值是 0，因此不能用 `flags & O_RDONLY` 判斷是不是只讀。取出存取模式時使用 `flags & O_ACCMODE`。

開啟模式不能超越檔案權限；要求寫入不代表 OS 一定允許。