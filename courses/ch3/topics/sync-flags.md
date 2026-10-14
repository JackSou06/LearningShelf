`O_SYNC` 要求 synchronized file integrity completion；`O_DSYNC` 要求 data integrity completion，差異在 metadata 完成條件。

`O_RSYNC` 是教材的讀取同步相關旗標，要與 O_SYNC／O_DSYNC 的條件一起理解；支援與實作因系統而異，不能把它當成通用的非同步讀取開關。

需要 O_SYNC 時在 open 設定。Linux 不支援用 F_SETFL 改變 O_SYNC／O_DSYNC；課本的效能討論也提到這個陷阱。