已經 open 之後，可用 fcntl 查詢或調整部分性質。`F_DUPFD` 可以配置大於等於指定下限的最低可用 fd；也有其他 ownership 與 locking 指令，相關細節留到後續章節。

GETFD / SETFD 的典型 flag 是 FD_CLOEXEC。GETFL / SETFL 常見例子是查詢或調整 O_APPEND、O_NONBLOCK 等可修改狀態。

**能查到不代表能修改。** 存取模式不能靠 F_SETFL 把只讀 fd 升級為讀寫；各 OS 可修改的 flags 集合也不完全一樣。