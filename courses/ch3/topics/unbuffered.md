`read(fd, buf, n)` 的 `buf` 就是程式提供的一塊記憶體。「Unbuffered」並不是說這塊記憶體不存在。

`fread()`、`fgets()`、`printf()` 屬於 C stdio；函式庫可以累積或預取資料，必要時才呼叫底層 `read/write`。

因此，**一次 stdio 呼叫不必然對應一次系統呼叫；一次 read 也不必然對應一次實體磁碟讀取。**