`openat(dirfd, "data.txt", O_RDONLY)` 以 dirfd 指向的目錄為起點。若傳入絕對路徑，dirfd 不參與定位；`AT_FDCWD` 則使用 current working directory。

固定目錄參考能減少目錄改名、工作目錄改變等帶來的競爭。但 **openat 本身不是所有 TOCTTOU 的解藥**：目錄下的目標仍可能在另一個檢查與開啟之間被替換。

不要先用 `access()` 檢查，再假設下一次 open 必定作用在同一個物件。能在操作本身表達條件時，應使用合適的操作與 flags。