`pread(fd, buf, n, offset)` 在指定位置讀取；`pwrite` 在指定位置寫入。它們避免使用共享 current offset 的「lseek + I/O」組合競爭。

但它們不是所有並行問題的解答：兩個 writer 若對同一範圍寫入，仍需要依需求協調，也仍要處理部分 I/O。

**Linux 補充**：依 Linux man-pages，帶 O_APPEND 的 fd 使用 pwrite 時可能仍追加，忽略指定寫入位置。需要定位寫入時，不要把這個組合當作跨平台保證。