Shell 常見流程：fork 出 child，在 child 內設定 fd，最後 exec 要執行的程式。成功的 exec 會替換程式映像，但一般 fd 可保留；FD_CLOEXEC 是例外。

當 cat 開始執行，它從 fd 0 讀入，向 fd 1 寫出。兩個 descriptor 已被接好，所以這些操作就在複製檔案。

下方是概念骨架，省略錯誤處理，並假設 a、b 都大於 2。真正的通用實作必須處理 fd 恰好等於 0 或 1 的情況。