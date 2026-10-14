`ioctl(fd, request, ...)` 可用於查詢 terminal 視窗大小等控制操作。Request 與所需資料結構依裝置、OS 而異，不是另一種普通 read。

`/dev/fd/0` 等名稱可以讓只接受 pathname 的工具使用既有輸入。教材常用「類似 dup」解釋其用途。

**平台差異**：/dev/fd 不是 POSIX 通用保證；Linux 的 /proc/self/fd 路徑與某些 BSD 的 descriptor duplication 語意有差異。不要推論在所有 OS 上 open("/dev/fd/n") 都與 dup(n) 完全等價、必定共享 offset。