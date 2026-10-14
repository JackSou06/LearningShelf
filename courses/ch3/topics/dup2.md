若 oldfd 有效且兩個號碼不同，newfd 原本已開啟時會被關閉，再改成指向 oldfd 的 entry；關閉與重用由 dup2 原子完成。

若 oldfd == newfd 且它有效，dup2 直接回傳這個 fd。若 oldfd 無效，呼叫失敗，不應先把 newfd 關掉。

現在先由 fd2 讀走 f，再執行 dup2(fd2, fd1)。觀察 A 消失與 fd1 的新指向，再預測後續讀取。