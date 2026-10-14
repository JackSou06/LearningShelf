User CPU time 是執行 user code 的 CPU 時間；system CPU time 是 Kernel 替程式執行服務的 CPU 時間；wall-clock time 是經過的真實時間，包含等待。

Read-ahead 可在循序存取時預先取得後面的資料，減少之後的等待；不是保證每種存取模式都有利。

課堂單執行緒情境中，CPU 時間總和通常不超過 wall time。多執行緒在多核心平行時，累積 CPU time 可以大於 wall time，不能把該不等式當成普遍規則。