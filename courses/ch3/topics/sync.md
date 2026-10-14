`fsync(fd)` 同步檔案資料與相關 metadata，並等待完成；`fdatasync(fd)` 偏向資料與正確讀回所必要的 metadata，例如延長後的 file size。

課本描述的 sync 標準最低保證允許排入寫出後返回。**Linux 的 sync 會等待 I/O 完成**，因此不能泛稱所有系統的 sync 都立刻返回。

同步不會自動包含 stdio 尚未 flush 的資料。若使用 FILE*，先處理 stdio 緩衝。新建／改名檔案的持久化還涉及目錄等細節，屬進一步系統設計議題。