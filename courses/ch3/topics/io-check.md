假設普通檔案內容是 `abcdef`，以 O_RDWR 開啟，所有呼叫成功。先 seek 到 2，讀 2 bytes，再寫 1 byte `X`。

請先寫下三項：讀到的內容、最後 offset、最後 file size。最後再推導檔案文字。