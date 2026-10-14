本章先介紹 `open`、`read`、`write`、`lseek`、`close`，再透過 `dup`、`fork` 與 `dup2` 理解共享與重新導向。

讀程式時，先找到 fd 指向的 open-file entry，再追蹤 offset、flags 與 file size。原子操作、I/O 效率與同步寫入也沿著這個模型理解。