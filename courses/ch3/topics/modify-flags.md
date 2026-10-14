開啟一個 flag 使用 `val |= flag`；關閉使用 `val &= ~flag`。兩次 fcntl 都要檢查失敗，不能在 GETFL 回傳 -1 後繼續拿它 OR。

這個模式保留其他可修改位元，但整組 GET/SET 不是跨呼叫原子更新；若其他執行者也會同時改同一 entry 的 flags，仍需要協調。

原教學以 O_SYNC 示範容易在 Linux 失效，本頁改用 O_APPEND。是否可修改，仍以目標系統的 fcntl 語意為準。