一般 fd 會在成功 exec 後保留；設了 FD_CLOEXEC 的 descriptor 則關閉，避免非必要資源流入新程式。

FD_CLOEXEC 屬於 descriptor。dup 建立的新 fd 通常清除此旗標；dup2 在 oldfd != newfd 且成功複製時也會清除 newfd 的 close-on-exec。相同有效 fd 的 no-op 情況保留原值。

需要在建立 fd 的同時就設定，可在支援的系統使用 open 的 O_CLOEXEC，避免先 open 再設定之間的時間空隙。