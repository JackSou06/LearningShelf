先寫入 10 bytes，offset=10、size=10。Seek 到 16384 時，offset 改成 16384，size 仍是 10。

再成功寫入 10 bytes，size 變為 16394。中間未寫入的範圍讀出來是值為 0 的 bytes，並不是字元 `'0'`。

邏輯長度看 size；實際配置量受檔案系統、區塊與 metadata 等影響。**只寫 20 bytes 不代表剛好只占 20 bytes 磁碟。** 複製是否保留稀疏性也取決於工具。