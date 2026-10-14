`dup(fd1)` 成功時回傳最低可用 fd。新 fd 有自己的 descriptor flags，但與原 fd 共用 offset 和 file status flags。

把上一頁的第二次 open 換成 dup，其他讀取步驟不變。預測答案後，按步驟觀察同一份 offset 如何前進。