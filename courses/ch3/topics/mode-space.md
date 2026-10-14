**User / kernel mode**：目前以什麼權限執行指令。**User / kernel space**：資料與程式所在的位址區域。

Kernel 替 process 處理 `read()` 時，必須受控地把資料寫到你提供的 user buffer。不能因此推論「Kernel 永遠不會存取 user space」。

課堂的位址圖是概念模型；實際映射、隔離機制與位址配置依架構及作業系統而異。