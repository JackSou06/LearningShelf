假設 open 回傳 3。`dup2(3, 1)` 讓 1 指向該檔案的 entry；再 close(3)，fd 1 仍持有它。

重新導向改的是連結，不是把 terminal 複製到檔案。`write(STDOUT_FILENO, ...)` 不必知道目的地的 pathname。

如果實際 open 回傳的就是 1，則不該再 close(1)。通用寫法是 `if (fd != STDOUT_FILENO) close(fd);`，並檢查前面各次呼叫是否成功。