**第一層：per-process descriptor table。** 每個 fd entry 有 descriptor flags 與指向 open-file entry 的參考。

**第二層：open-file entry（open file description）。** 放 current offset、file status flags 與檔案物件的參考。不同 fd 可以指向同一個 entry。

**第三層：vnode/inode 概念層。** 表示檔案相關資訊，例如 file size、權限與區塊資訊。這是 APUE 的概念模型，各 OS 的實際資料結構名稱不一定相同。