下例 fd1、fd2 共用 A，fd3 自己指向 B；A 和 B 對應相同檔案。

對 fd1 執行 F_SETFD 設定 FD_CLOEXEC，只改 fd1 自己的 descriptor entry。對 fd1 執行 F_SETFL 設定可修改的 O_APPEND，則 A 的所有使用者都會看見改變。

本例假設呼叫成功，且使用目標系統支援的 flag。