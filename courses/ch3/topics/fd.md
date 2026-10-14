兩個 process 都可以有 `fd = 3`，卻指向完全不同的檔案。同一個 process 也可以用不同 fd 存取同一個檔案。

常見的 `0 / 1 / 2` 分別作為標準輸入、標準輸出、標準錯誤。程式可使用 `STDIN_FILENO`、`STDOUT_FILENO`、`STDERR_FILENO` 表達用途。

這些 fd 通常由 shell／父 process 準備。**0、1、2 不保證一定接 terminal，也不保證一定都開著。**