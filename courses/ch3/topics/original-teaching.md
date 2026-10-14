# CH3 — File I/O（Unbuffered I/O）

> 依據：
> - 老師投影片 `sp_ch3_2026.pdf`
> - 老師上課字幕 `I_O_lecture.txt`（已依投影片與 APUE 校正辨識錯誤）
> - *Advanced Programming in the UNIX Environment, 3rd Edition*，Chapter 3

本章重點不是死背 API，而是建立一個完整的 UNIX File I/O 模型：

1. `open()` 怎麼讓 process 取得檔案
2. file descriptor 到底是什麼
3. Kernel 怎麼表示「已開啟的檔案」
4. `read()` / `write()` 如何影響 file offset
5. `lseek()` 為什麼不真的做 I/O
6. 同一檔案 `open()` 兩次、`dup()`、`fork()` 的差別
7. concurrent access 為什麼會產生 race condition
8. `O_APPEND`、`pread()`、`pwrite()` 如何提供 atomicity
9. `dup2()` 如何實現 I/O redirection
10. buffer size 如何影響 I/O efficiency
11. 為什麼 `write()` 成功不代表資料已經真的寫入 disk
12. `sync()` / `fsync()` / `fdatasync()` 做什麼
13. `fcntl()` 如何改已經 open 的檔案屬性
14. `ioctl()`、`/dev/fd` 是什麼

---

# 0. 先建立整章的核心圖

老師上課一直強調：**第三章最重要的不是 API 名字，而是你能不能把每個 API 對回 Kernel 裡面的資料結構。**

```text
                 User Process
                      │
             File Descriptor
                      │
      ┌───────────────▼────────────────┐
      │ Open File Descriptor Table     │  ← 每個 process 自己一份
      │ fd 0 → pointer                 │
      │ fd 1 → pointer                 │
      │ fd 2 → pointer                 │
      │ fd 3 → pointer                 │
      └───────────────┬────────────────┘
                      │
──────────────────────┼──────── Kernel ────────────────
                      │
      ┌───────────────▼────────────────┐
      │ System Open File Table         │  ← 全系統共享
      │ file status flags              │
      │ current file offset            │
      │ vnode/inode pointer            │
      │ reference count                │
      └───────────────┬────────────────┘
                      │
      ┌───────────────▼────────────────┐
      │ vnode / inode                  │
      │ metadata                       │
      │ file size                      │
      │ owner / permissions / blocks   │
      └───────────────┬────────────────┘
                      │
                 Buffer/Page Cache
                      │
                    Disk
```

之後看到任何 API，都問：

> 它到底是在修改這張圖的哪一部分？

---

# 1. System Call 和普通 Function Call 有什麼不同？

## 現在在學什麼？

以前寫 C 時，我們常常覺得：

```c
printf(...);
fopen(...);
read(...);
```

全部都只是「呼叫函式」。

但系統程式設計開始要區分：

- 普通 function call
- library function
- system call

這三者不一定在同一層。

---

## 普通 Function Call

例如：

```c
int add(int a, int b)
{
    return a + b;
}
```

呼叫：

```c
x = add(1, 2);
```

基本上只是：

```text
你的程式
   ↓
add()
   ↓
回到你的程式
```

CPU 仍然在：

```text
user mode
```

執行。

---

## System Call

例如：

```c
read(fd, buf, 100);
```

這就不只是普通 function call。

因為 read 可能要：

- 檢查 file descriptor
- 檢查權限
- 查 filesystem
- 查 page cache
- 操作 device driver
- 等 disk

這些事情不能由一般 user program 直接做。

所以流程概念是：

```text
User Program
    │
    │ read()
    ▼
System Call Interface
    │
    │ trap
    ▼
Kernel
    │
    ├─ check fd
    ├─ check permission
    ├─ locate open-file entry
    ├─ filesystem
    └─ I/O
```

CPU privilege level 會：

```text
user mode
   ↓
kernel mode
   ↓
執行 OS code
   ↓
user mode
```

這個切換叫做：

> mode switch

---

# 2. User Mode / Kernel Mode 和 User Space / Kernel Space 不一樣

## 現在在學什麼？

這兩組名詞很容易混。

### User Mode / Kernel Mode

講的是：

> CPU 現在用什麼 privilege level 執行 instruction

### User Space / Kernel Space

講的是：

> memory address space 的區域

---

## 正確概念

User mode：

```text
可以 access 自己的 user space
不能任意 access kernel space
```

Kernel mode：

```text
可以 access kernel space
也可以 access user space
```

所以不是：

```text
kernel mode → 只能存取 kernel space   ❌
```

而是：

```text
kernel mode → privilege 比較高
```

---

# 3. `printf()`、`fopen()` 為什麼不是 System Call？

## 現在在學什麼？

很多 C library function 最後仍然會偷偷幫你呼叫 system call。

例如：

```c
printf("hello\n");
```

概念上：

```text
your program
   ↓
printf()
   ↓
C stdio library
   ↓
write()
   ↓
kernel
```

所以：

```text
printf ≠ system call
write  = system call
```

---

同樣：

```c
FILE *fp = fopen("a.txt", "r");
```

概念：

```text
fopen()
   ↓
C library
   ↓
open()
   ↓
kernel
```

但是 `fopen()` 還會多做：

- 建立 `FILE` object
- 建立 stdio buffer
- 紀錄 file descriptor
- 管理 buffered I/O 狀態

所以：

```c
FILE *fp;
```

屬於：

> Standard I/O / Buffered I/O

而：

```c
int fd;
```

屬於：

> File I/O / Unbuffered I/O

---

# 4. 到底什麼叫 Unbuffered I/O？

## 現在在學什麼？

這章最大的陷阱之一：

> Unbuffered I/O **不是**「整個系統完全沒有 buffer」。

Chapter 3 主要 API：

```text
open
close
read
write
lseek
dup
dup2
fcntl
ioctl
```

這些通常稱為：

> unbuffered I/O

---

## 真正意思

例如：

```c
read(fd, buf, n);
```

每一次 `read()` 都會進 kernel。

```text
User Process
    │
 read()
    │
────▼──────── kernel boundary
Kernel Buffer / Page Cache
    │
   Disk
```

注意：

> Kernel buffer 還是在。

沒有的是：

```text
C stdio library 自動維護的 user-space buffer
```

---

## Buffered I/O 則多一層

```text
User Process

fscanf / fread / fgets
        │
        ▼
┌──────────────────┐
│ stdio buffer     │ ← C library buffer
└────────┬─────────┘
         │ 必要時才 read()
─────────▼────────────────
Kernel buffer/page cache
         │
        Disk
```

所以一句話記：

> **Unbuffered I/O means no automatic buffering in user space, not no buffering in the system.**

---

# 5. 為什麼 Kernel 還需要 Buffer Cache？

## 現在在學什麼？

假設：

```c
char c;
read(fd, &c, 1);
```

你只讀 1 byte。

但 storage device 通常不是 1 byte、1 byte 去做 I/O。

---

## HDD

傳統 disk 通常以 block 為單位存取。

所以即使你只要：

```text
1 byte
```

OS 很可能會讀：

```text
整個 block / page
```

然後放進 memory cache。

---

## SSD 也不是完全「逐 byte」

Flash 常見結構：

```text
Block
 ├─ Page
 ├─ Page
 ├─ Page
 └─ Page
```

通常：

```text
read  → page
write → page
erase → block
```

而且 flash 很多情況不能直接 overwrite 已寫入 page。

因此可能需要：

```text
read old data
modify in memory
erase block
rewrite
```

這就是 SSD 常見的：

> write amplification

---

## Buffer Cache 的目的

第一次：

```text
Program
   ↓ read()
Kernel
   ↓
Cache miss
   ↓
Disk
   ↓
把整個 block/page 放進 cache
```

下一次讀附近資料：

```text
Program
   ↓ read()
Kernel
   ↓
Cache hit
   ↓
直接返回
```

所以：

> `read()` system call 不代表每一次都真的碰到 disk。

---

# 6. File Descriptor 到底是什麼？

## 現在在學什麼？

UNIX 裡面，process 對 open file 的操作都透過：

> file descriptor

File descriptor 是：

> non-negative integer

例如：

```c
int fd;

fd = open("hello.txt", O_RDONLY);
```

可能得到：

```text
fd = 3
```

---

## `3` 不是檔案 ID

不是：

```text
3 = hello.txt 的永久編號
```

而是：

```text
3 = 這個 process 的
    Open File Descriptor Table 的 index
```

例如：

```text
Process A

index
  0   stdin
  1   stdout
  2   stderr
  3   → hello.txt
  4   → other
```

所以：

```text
fd = 3
```

真正意思是：

> 去我的 descriptor table 看第 3 格。

---

# 7. 為什麼第一個 `open()` 常常得到 3？

因為 shell 通常已經幫 process 設好：

```text
0 = standard input
1 = standard output
2 = standard error
```

C / POSIX 裡建議寫：

```c
STDIN_FILENO
STDOUT_FILENO
STDERR_FILENO
```

而不是硬寫：

```c
0
1
2
```

---

# 8. `open()` 會回傳哪一個 fd？

UNIX 的規則：

> 回傳目前最低號碼、尚未使用的 file descriptor。

例如：

```text
0 used
1 used
2 used
3 used
4 free
5 free
```

下一次：

```c
open(...)
```

回傳：

```text
4
```

---

如果：

```c
close(1);
```

變：

```text
0 used
1 free
2 used
3 used
```

下一次：

```c
open(...)
```

可能回傳：

```text
1
```

這個特性之後會變成：

> I/O redirection 的基礎。

---

# 9. Kernel 裡的三層 File Data Structure

## 現在在學什麼？

這是 Chapter 3 最重要的圖。

---

## 第一層：Open File Descriptor Table

每個 process 自己一份。

```text
Process A

fd      flags       pointer
0       ...    ──────────────►
1       ...    ──────────────►
2       ...    ──────────────►
3       ...    ──────────────►
```

每個 descriptor entry 主要有：

```text
file descriptor flags
pointer → system open file table
```

重要 descriptor flag：

```text
FD_CLOEXEC
```

---

## 第二層：System Open File Table

由 kernel 維護，system-wide。

每個 entry 會紀錄：

```text
file status flags
current file offset
vnode/inode pointer
reference count
```

例如：

```text
System Open File Table Entry

flags = O_RDONLY
current offset = 125
vnode ptr ─────► ...
reference count = 2
```

---

## 第三層：v-node / inode

代表：

> 真正的 file object / filesystem metadata

可能包含：

```text
owner
permissions
file size
device
data block info
timestamps
...
```

---

# 10. 最重要的一組區分：Current Offset vs File Size

## 現在在學什麼？

假設：

```text
foobar
```

總共有：

```text
6 bytes
```

所以：

```text
file size = 6
```

File size 屬於：

```text
vnode / inode
```

---

而 current file offset 是：

> 這一次 open 現在讀到哪裡。

放在：

```text
System Open File Table Entry
```

所以一定要背：

```text
File size      → vnode/inode
Current offset → Open File Table
```

---

# 11. `open()`

## 現在在學什麼？

`open()` 建立的是：

```text
Process
  ↓
File Descriptor
  ↓
Open File Table Entry
  ↓
inode/vnode
```

prototype：

```c
#include <fcntl.h>

int open(const char *pathname, int oflag, ...);
```

成功：

```text
return fd >= 0
```

失敗：

```text
return -1
errno 被設定
```

---

## Kernel 概念上做什麼？

```text
1. 找 pathname
2. 檢查 permission
3. 建立 open-file entry
4. 連到 inode/vnode
5. 找 process fd table 最低空位
6. 指向 open-file entry
7. return fd
```

---

# 12. `O_RDONLY / O_WRONLY / O_RDWR`

## 現在在學什麼？

這些是：

> 這一次 open 的 access mode

例如：

```c
open("a.txt", O_RDONLY);
```

意思：

```text
這次 open 只能 read
```

不是：

```text
a.txt 永遠只能 read
```

另一個 process 仍然可以：

```c
open("a.txt", O_WRONLY);
```

於是：

```text
             same inode
             ▲       ▲
             │       │
Open Entry A │       │ Open Entry B
O_RDONLY             O_WRONLY
offset 10            offset 53
```

---

# 13. `O_CREAT / O_TRUNC / O_EXCL`

## `O_CREAT`

如果檔案不存在：

```text
create
```

例如：

```c
open("a.txt",
     O_WRONLY | O_CREAT,
     0644);
```

有 `O_CREAT` 時才需要 mode。

---

## `O_TRUNC`

如果檔案存在且可以 write：

```text
file size → 0
```

所以：

```c
open("a.txt",
     O_WRONLY | O_TRUNC);
```

可能直接把原內容清掉。

---

## `O_EXCL`

通常和：

```c
O_CREAT | O_EXCL
```

一起用。

行為：

```text
檔案不存在
→ create 成功

檔案已存在
→ open 失敗
```

最重要的是：

> existence check + creation 是 atomic operation。

---

# 14. mode 與 umask

## 現在在學什麼？

你指定：

```c
open("a.txt",
     O_CREAT | O_WRONLY,
     0777);
```

不代表最後一定是：

```text
0777
```

還要套：

> umask

假設：

```text
requested = 0777
umask     = 0022
```

則：

```text
actual = requested & ~umask
       = 0755
```

---

常見 symbol：

```c
S_IRUSR
S_IWUSR
S_IXUSR

S_IRGRP
S_IWGRP
S_IXGRP

S_IROTH
S_IWOTH
S_IXOTH
```

---

# 15. `creat()`

## 現在在學什麼？

`creat()` 是歷史留下來的 API。

```c
int creat(const char *pathname, mode_t mode);
```

等價：

```c
open(pathname,
     O_WRONLY | O_CREAT | O_TRUNC,
     mode);
```

所以現在通常直接用：

```c
open()
```

就可以。

---

# 16. `close()`

## 現在在學什麼？

`close(fd)` 不是：

> 刪除檔案。

而是：

> 移除這個 process descriptor 對 open-file entry 的 reference。

例如：

```text
fd3 ─────► Open File Entry
```

做：

```c
close(3);
```

變：

```text
fd3 ───X
```

Open File Entry 的：

```text
reference count
```

也會減少。

如果：

```text
2 → 1
```

entry 還不能釋放。

如果：

```text
1 → 0
```

才有機會釋放。

---

# 17. `openat()` 和 TOCTTOU

## 現在在學什麼？

`openat()` 可以：

> 以某個 directory fd 作為相對路徑起點。

prototype：

```c
int openat(int dirfd,
           const char *pathname,
           int oflag,
           ...);
```

如果 `pathname` 是 absolute path：

```text
openat ≈ open
```

如果：

```c
dirfd == AT_FDCWD
```

則相對於：

```text
current working directory
```

---

## 為什麼需要 `openat()`？

其中一個理由：

> 避免 pathname race / TOCTTOU

TOCTTOU：

> Time Of Check To Time Of Use

例如：

```c
if (access("A/file", W_OK) == 0)
    open("A/file", O_WRONLY);
```

可能發生：

```text
check A/file
       ↓
   context switch
       ↓
A/file 被換掉
       ↓
open A/file
```

你 check 的 object 和最後 open 的 object：

```text
可能不是同一個
```

所以：

```text
Time of Check
    ≠
Time of Use
```

這就是 TOCTTOU。

---

# 18. Blocking 和 Synchronization 不要混在一起

## 現在在學什麼？

兩條完全不同的概念。

---

## Blocking / Non-blocking

描述：

> function call 什麼時候 return

例如 pipe 沒資料。

Blocking read：

```text
read()
 │
 │ 等
 │ 等
 │
 ▼
有資料
 │
return
```

Nonblocking：

```text
read()
 │
沒有資料
 │
立即 return
```

---

## Synchronous / Asynchronous

則是在描述：

> I/O data movement 的完成要求與時機。

所以：

```text
nonblocking ≠ asynchronous
blocking ≠ synchronous
```

---

# 19. `lseek()`：改 Current File Offset

## 現在在學什麼？

`lseek()` 用來：

> 改 current file offset。

prototype：

```c
#include <unistd.h>

off_t lseek(int fd,
            off_t offset,
            int whence);
```

---

## `SEEK_SET`

```c
lseek(fd, 100, SEEK_SET);
```

意思：

```text
offset = 100
```

---

## `SEEK_CUR`

```c
lseek(fd, 10, SEEK_CUR);
```

意思：

```text
offset = old_offset + 10
```

---

## `SEEK_END`

```c
lseek(fd, -10, SEEK_END);
```

意思：

```text
offset = file_size - 10
```

---

# 20. `lseek(fd, 0, SEEK_CUR)` 有什麼用？

```c
off_t currpos =
    lseek(fd, 0, SEEK_CUR);
```

因為：

```text
current + 0
```

所以可以：

> 查詢現在 current file offset。

---

# 21. `lseek()` 本身會不會做 I/O？

答案：

> 不會。

例如：

```c
lseek(fd, 1000000, SEEK_SET);
```

Kernel 只是改：

```text
Open File Table
current offset = 1000000
```

並沒有：

```text
讀 disk
寫 disk
```

真正 I/O 要等：

```c
read(...)
write(...)
```

---

# 22. 哪些東西不能 `lseek()`？

Regular File：

```text
可以
```

Pipe：

```text
不可以
```

FIFO：

```text
不可以
```

Socket：

```text
不可以
```

因為 pipe/socket 是：

```text
stream
```

不是 random-access file。

對 pipe / FIFO / socket 做 `lseek()`，標準錯誤通常是：

```text
ESPIPE
```

---

# 23. Sparse File / File Hole

## 現在在學什麼？

為什麼 file logical size：

```text
很大
```

不代表 disk usage：

```text
一樣大
```

例如：

```c
write(fd, "abcdefghij", 10);

lseek(fd, 16384, SEEK_SET);

write(fd, "ABCDEFGHIJ", 10);
```

結果：

```text
offset
0        10                     16384      16394
│---------│.......................│----------│
 abcdefghij          HOLE          ABCDEFGHIJ
```

Logical file size：

```text
16394 bytes
```

但中間：

```text
10 ~ 16383
```

可能完全沒有配置 physical data block。

這叫：

> sparse file

---

## 讀 hole 會怎樣？

讀出來會像：

```text
\0 \0 \0 \0 ...
```

但：

```text
邏輯上讀到 zero
```

不代表 disk 上真的存了一大堆 zero。

---

# 24. `read()`

## 現在在學什麼？

從：

> current file offset

開始讀資料。

prototype：

```c
ssize_t read(int fd,
             void *buf,
             size_t nbytes);
```

例如：

```c
char buf[100];

ssize_t n =
    read(fd, buf, 100);
```

意思：

> 最多讀 100 bytes。

不是：

> 保證一定讀 100 bytes。

---

## Return Value

```text
> 0   實際讀到的 bytes
= 0   EOF
= -1  error
```

---

# 25. Short Read

例如：

```c
read(fd, buf, 1000);
```

可能只 return：

```text
300
```

原因可能是：

- EOF
- terminal line input
- network
- pipe
- record-oriented device
- signal

所以：

```text
read 少於 nbytes
```

不一定是 error。

---

# 26. EOF 為什麼 return 0？

如果：

```text
file size = 100
current offset = 100
```

再做：

```c
read(...)
```

已經沒有資料：

```text
return 0
```

代表：

> End Of File

---

# 27. Signal 可能中斷 System Call

## 現在在學什麼？

System call return error：

> 不一定代表真正操作失敗。

例如 process 正在：

```text
read()
```

突然收到 signal。

可能：

```text
read() → -1
errno = EINTR
```

所以 robust code 常寫：

```c
do {
    n = read(fd, buf, size);
} while (n < 0 && errno == EINTR);
```

意思：

> 如果只是被 signal 打斷，再做一次。

---

# 28. `write()`

## 現在在學什麼？

從 current offset 開始寫。

prototype：

```c
ssize_t write(int fd,
              const void *buf,
              size_t nbytes);
```

例如：

```c
write(fd, "ABC", 3);
```

如果原本：

```text
offset = 10
```

寫完：

```text
10 11 12
 A  B  C
```

然後：

```text
offset = 13
```

---

## Write 可能失敗

常見：

```text
disk full
file-size limit
signal
```

---

# 29. `O_APPEND` 是超級重要的特例

## 現在在學什麼？

Append 不是：

> open 時把 offset 放到 EOF 一次。

真正是：

> 每一次 write 前，都重新定位到目前的 EOF。

假設：

```text
file size = 100
current offset = 20
```

如果 open-file entry 有：

```text
O_APPEND
```

呼叫：

```c
write(fd, buf, 10);
```

Kernel 概念上：

```text
offset = current file size   // 100
write
```

最後：

```text
file size = 110
offset = 110
```

---

# 30. I/O Efficiency：為什麼不能一次只讀 1 byte？

## 現在在學什麼？

System call 有 overhead。

例如：

```c
char c;

while (read(fd, &c, 1) > 0)
    write(out, &c, 1);
```

如果 file 是 100 MB：

```text
約一億次 read
約一億次 write
```

每次都要：

```text
user mode
→ system call
→ kernel
→ check
→ copy
→ return
→ user mode
```

所以超慢。

---

## 改成大 buffer

```c
char buf[8192];

while ((n = read(fd, buf, sizeof(buf))) > 0)
    write(out, buf, n);
```

system call 次數就大幅下降。

---

## 最重要的概念

不是：

```text
8192 永遠是最佳值
```

而是：

```text
buffer 太小
→ system call overhead 很大

buffer 增大
→ syscall 次數下降

大到某個程度後
→ 收益開始趨近飽和
```

---

# 31. Read-ahead

## 現在在學什麼？

如果 OS 發現你 sequential read：

```text
讀 block 0
讀 block 1
讀 block 2
```

它可能開始預測：

> 你等等應該還要讀下一個。

所以：

```text
你要求 block 10
```

Kernel 可能順便讀：

```text
11
12
13
...
```

這叫：

> read-ahead / prefetch

下一次真的要 block 11：

```text
page cache hit
```

就不用等 disk。

---

# 32. User CPU / System CPU / Wall-clock Time

## User CPU Time

CPU 在：

```text
user mode
```

執行你的 code 的時間。

---

## System CPU Time

CPU 在：

```text
kernel mode
```

幫你的 process 執行 system call / OS code 的時間。

---

## Wall-clock Time

從：

```text
程式開始
```

到：

```text
程式真的結束
```

中間所有時間。

所以：

```text
User CPU + System CPU <= Wall Clock
```

因為可能有：

```text
等 disk
等 network
blocked
被 scheduler 換出去
sleep
```

---

# 33. Delayed Write

## 現在在學什麼？

`write()` return 成功：

> 不代表資料已經真的寫進 physical storage。

正常可能是：

```text
Application
    │
 write()
    ▼
Kernel Page Cache
    │
    │ return
    ▼
Application 繼續執行

稍後
    ↓
Kernel flush
    ↓
Disk
```

這叫：

> delayed write

---

## 好處

```text
不用每次 write 都等 disk
```

效能高很多。

---

## 風險

```text
write() 已成功
     ↓
資料還在 RAM cache
     ↓
突然斷電
     ↓
資料可能消失
```

所以才需要：

```text
fsync
fdatasync
O_SYNC
```

---

# 34. File Sharing：同一檔案 `open()` 兩次

## 現在在學什麼？

同一個 pathname：

> 不代表共用 current offset。

假設：

```c
fd1 = open("foobar.txt", O_RDONLY);
fd2 = open("foobar.txt", O_RDONLY);
```

而：

```text
foobar.txt = "foobar"
```

結構：

```text
Process FD Table

fd1 ───► Open Entry A
             offset = 0
               │
               ▼
             inode ───► foobar.txt

fd2 ───► Open Entry B
             offset = 0
               │
               └────────► same inode
```

所以兩個 `open()`：

```text
兩個不同 Open File Table Entry
```

offset：

```text
各自獨立
```

---

## 範例

```c
read(fd1, &c, 1);
```

變：

```text
Entry A offset = 1
Entry B offset = 0
```

再：

```c
read(fd2, &c, 1);
```

還是從 offset 0：

```text
'f'
```

---

# 35. `fork()` 後就不一樣

## 現在在學什麼？

Child 會繼承 parent's file descriptors。

假設：

```c
fd = open("foobar.txt", O_RDONLY);

fork();
```

概念：

```text
Parent FD Table
fd ───────┐
          │
          ▼
      Open File Table
       offset = 0
          ▲
          │
Child FD Table
fd ───────┘
```

Parent 和 child：

```text
descriptor table 是兩份
```

但是：

```text
pointer 指向同一個 Open File Table Entry
```

所以共享：

```text
current offset
file status flags
```

---

# 36. `fork()` 題目

```c
fd = open("foobar.txt", O_RDONLY);

if (fork() == 0) {
    read(fd, &c, 1);
    exit(0);
}

wait(NULL);

read(fd, &c, 1);

printf("%c\n", c);
```

Child 先讀：

```text
f
offset 0 → 1
```

Parent wait 完再讀：

```text
offset = 1
```

所以讀到：

```text
o
```

答案：

```text
o
```

---

# 37. Atomic Operation

## 現在在學什麼？

兩個 system call 雖然程式碼寫在一起：

> 中間仍然可能被 scheduler 插隊。

例如：

```c
lseek(fd, 0, SEEK_END);
write(fd, buf, 10);
```

你心裡把它當：

```text
append
```

但是 OS 看的是：

```text
operation 1 = lseek
operation 2 = write
```

---

## Race Example

Process A：

```text
A: lseek → EOF = 100
```

Scheduler 換 B：

```text
B: lseek → EOF = 100
B: write → 100~109
```

再換回 A：

```text
A: write → 100~109
```

結果：

> A 把 B 覆蓋掉。

---

# 38. `O_APPEND` 如何解 Race？

## 現在在學什麼？

如果：

```c
open(path,
     O_WRONLY | O_APPEND);
```

每次：

```c
write(fd, buf, 10);
```

kernel 會原子處理：

```text
定位目前 EOF
+
write
```

所以不需要：

```c
lseek(...);
write(...);
```

---

可能結果：

```text
AAAA BBBB
```

或：

```text
BBBB AAAA
```

但不應該因為兩邊都拿到舊 EOF 而互相覆蓋。

---

# 39. `pread()` / `pwrite()`

## 現在在學什麼？

我要在指定 offset 做 I/O：

> 但不想用 `lseek()+read/write()` 兩個 system call。

---

## `pread`

```c
ssize_t pread(int fd,
              void *buf,
              size_t nbytes,
              off_t offset);
```

概念類似：

```c
lseek(fd, offset, SEEK_SET);
read(fd, buf, nbytes);
```

但：

```text
position + read
```

是一個 atomic positioned I/O。

而且：

> 不會修改 shared current file offset。

---

## `pwrite`

```c
ssize_t pwrite(int fd,
               const void *buf,
               size_t nbytes,
               off_t offset);
```

概念類似：

```text
seek + write
```

同樣：

> 不會改 normal current file offset。

---

# 40. `O_CREAT | O_EXCL` 也是 Atomicity

## 現在在學什麼？

Check-then-act 很容易產生 race。

錯誤：

```c
fd = open(path, O_WRONLY);

if (fd < 0 && errno == ENOENT)
    fd = creat(path, mode);
```

可能：

```text
Process A: check → 不存在

                    Process B: create
                    Process B: write

Process A: creat()
```

而 `creat()` 可能 truncate。

所以：

```c
open(path,
     O_WRONLY | O_CREAT | O_EXCL,
     mode);
```

把：

```text
check
+
create
```

合成 atomic operation。

---

# 41. `dup()`：Duplicate File Descriptor

## 現在在學什麼？

`dup()` 不是：

> 再 open 一次。

而是：

> 再建立一個 descriptor，指向同一個 open-file entry。

prototype：

```c
int dup(int fd);
```

例如：

```c
int fd1 = open("a.txt", O_RDONLY);

int fd2 = dup(fd1);
```

變：

```text
fd1 ────┐
        │
        ▼
      Open File Entry
        ▲
        │
fd2 ────┘
```

所以共享：

```text
current offset
file status flags
```

---

## `dup()` 回傳哪個 fd？

規則：

> lowest available file descriptor

---

# 42. `open()` 兩次 vs `dup()`

## `open()` twice

```c
fd1 = open("a.txt", O_RDONLY);
fd2 = open("a.txt", O_RDONLY);
```

結構：

```text
fd1 ──► Open Entry A ──┐
                       ▼
                     inode
                       ▲
fd2 ──► Open Entry B ──┘
```

offset：

```text
獨立
```

---

## `dup()`

```c
fd1 = open("a.txt", O_RDONLY);
fd2 = dup(fd1);
```

結構：

```text
fd1 ──┐
      ▼
   Open Entry ──► inode
      ▲
fd2 ──┘
```

offset：

```text
共享
```

這兩張圖一定要會畫。

---

# 43. `dup2()`：I/O Redirection 的核心

## 現在在學什麼？

prototype：

```c
int dup2(int oldfd, int newfd);
```

意思：

> 讓 `newfd` 變成 `oldfd` 的 duplicate。

老師上課的記法：

> 後面的指向前面的。

例如：

```c
dup2(fd2, fd1);
```

最後：

```text
fd1
```

會指向：

```text
fd2 原本指向的 open-file entry
```

---

## 如果 `newfd` 原本已 open？

先：

```text
close(newfd)
```

再 redirect。

但是這整件事由 `dup2()` 原子完成。

---

# 44. `dup2()` 題目

假設：

```text
foobar.txt = "foobar"
```

程式：

```c
fd1 = open("foobar.txt", O_RDONLY);
fd2 = open("foobar.txt", O_RDONLY);

read(fd2, &c, 1);

dup2(fd2, fd1);

read(fd1, &c, 1);

printf("%c\n", c);
```

開始：

```text
fd1 → Entry A offset 0
fd2 → Entry B offset 0
```

先：

```c
read(fd2, &c, 1);
```

結果：

```text
c = f
Entry B offset = 1
```

再：

```c
dup2(fd2, fd1);
```

變：

```text
fd1 ─┐
     ▼
   Entry B offset 1
     ▲
fd2 ─┘
```

所以：

```c
read(fd1, &c, 1);
```

會從 offset 1：

```text
o
```

答案：

```text
o
```

---

# 45. `dup2()` 做 Output Redirection

## 現在在學什麼？

為什麼：

```c
printf(...)
```

可以突然不寫 terminal，而是寫進 file。

程式：

```c
fd = open("file",
          O_WRONLY | O_CREAT | O_TRUNC,
          0666);

dup2(fd, STDOUT_FILENO);

close(fd);

printf("Hello\n");
```

---

## 原本

假設：

```text
fd = 3
```

則：

```text
1 → Terminal
3 → file
```

---

## `dup2(3, 1)`

變：

```text
1 ─┐
   ▼
 file
   ▲
3 ─┘
```

---

## `close(3)`

變：

```text
1 ─────► file
```

所以：

```c
printf(...)
```

最後寫的是：

```text
stdout = fd 1
```

但 fd 1 現在：

```text
指向 file
```

所以輸出進 file。

這就是 shell：

```bash
./a.out > file
```

背後的核心原理。

---

# 46. 為什麼 `close(fd)` 不會把 stdout 一起關掉？

因為：

```text
fd 1 ─┐
      ▼
   Open Entry
      ▲
fd 3 ─┘
```

reference count：

```text
2
```

`close(3)`：

```text
2 → 1
```

Open File Entry 還有人指向：

```text
fd 1
```

所以仍然存在。

---

# 47. `fork + dup2 + exec` = Shell 的核心技術

## 現在在學什麼？

Shell 怎麼做：

```bash
command < input > output
```

典型概念：

```c
fd1 = open(argv[1], O_RDONLY);

dup2(fd1, 0);
close(fd1);

fd2 = open(argv[2],
           O_WRONLY | O_TRUNC | O_CREAT,
           0644);

dup2(fd2, 1);
close(fd2);

execve("/bin/cat", newargv, envp);
```

在 `execve()` 前：

```text
fd 0 → file1
fd 1 → file2
```

然後 exec `/bin/cat`。

`cat` 只知道：

```text
read stdin
write stdout
```

所以實際就是：

```text
read file1
write file2
```

這就是 UNIX redirection 很漂亮的地方：

> 被執行的程式不需要知道 shell 幫它 redirect 過。

---

# 48. `printf()` 為什麼有時候不會立刻顯示？

## 現在在學什麼？

Chapter 3 的 unbuffered I/O 和 Chapter 5 stdio buffer 要接起來。

例如：

```c
printf("hello");
```

不一定馬上：

```text
write(1, ...)
```

可能只是：

```text
printf
  ↓
stdio buffer
```

如果 stdout 連 terminal，常見是：

> line buffered

所以：

```c
printf("hello\n");
```

換行可能觸發：

```text
flush
 ↓
write()
 ↓
kernel
```

如果沒有 `\n`：

```c
printf("hello");
```

資料可能暫時只待在 user-space buffer。

可以手動：

```c
fflush(stdout);
```

---

# 49. `sync()` / `fsync()` / `fdatasync()`

## 現在在學什麼？

控制：

> kernel delayed-write cache 什麼時候同步到 storage。

---

## `sync()`

```c
void sync(void);
```

概念：

```text
把 dirty buffers 排進 write queue
然後 return
```

通常不保證：

```text
等所有 disk write 完成
```

才 return。

---

## `fsync(fd)`

```c
int fsync(int fd);
```

針對：

> 指定 file

而且會等待同步完成。

通常包括：

```text
file data
+
相關 metadata
```

常用場景：

```text
database
transaction log
important config
```

---

## `fdatasync(fd)`

很像 `fsync()`。

重點：

```text
data synchronization
```

通常比同步所有不必要 metadata 更精簡。

---

# 50. `O_SYNC / O_DSYNC / O_RSYNC`

## 現在在學什麼？

不是：

> write 完再手動 sync。

而是：

> open 時直接設定同步策略。

---

## `O_SYNC`

每次：

```c
write(...)
```

都要達到同步完成條件後才 return。

所以：

```text
durability ↑
performance ↓
```

---

## `O_DSYNC`

較偏：

```text
data synchronization
```

---

## `O_RSYNC`

和 read / pending write synchronization 有關。

---

# 51. `fcntl()`

## 現在在學什麼？

檔案已經 open 了：

> 現在想查或修改 descriptor / open-file properties。

prototype：

```c
#include <fcntl.h>

int fcntl(int fd, int cmd, ...);
```

常見用途：

```text
1. duplicate descriptor
2. get/set descriptor flags
3. get/set file status flags
4. async I/O ownership
5. record locking
```

---

# 52. `F_GETFD / F_SETFD`

## 現在在學什麼？

操作：

> file descriptor flags

位置：

```text
Process File Descriptor Table
```

最重要：

```text
FD_CLOEXEC
```

所以：

```c
fcntl(fd, F_SETFD, ...);
```

只影響：

```text
那一個 fd entry
```

---

# 53. `F_GETFL / F_SETFL`

## 現在在學什麼？

操作：

> file status flags

位置：

```text
System Open File Table Entry
```

例如：

```text
O_APPEND
O_NONBLOCK
O_SYNC
```

---

# 54. `F_SETFD` vs `F_SETFL` 超級重要題

假設：

```c
fd1 = open(pathname, oflags);

fd2 = dup(fd1);

fd3 = open(pathname, oflags);
```

結構：

```text
fd1 ─┐
     ▼
   Entry A ─────────┐
     ▲              │
fd2 ─┘              ▼
                   inode
                    ▲
fd3 ─────► Entry B ─┘
```

---

## `F_SETFD`

```c
fcntl(fd1, F_SETFD, ...);
```

改：

```text
fd1 那一格
```

所以只影響：

```text
fd1
```

不影響：

```text
fd2
fd3
```

---

## `F_SETFL`

```c
fcntl(fd1, F_SETFL, ...);
```

改：

```text
Entry A
```

所以影響：

```text
fd1
fd2
```

不影響：

```text
fd3
```

---

# 55. 修改 flags 要 Get → Modify → Set

錯誤：

```c
fcntl(fd, F_SETFL, O_SYNC);
```

可能把其他原本的 flags 清掉。

正確：

```c
int val;

val = fcntl(fd, F_GETFL);

val |= O_SYNC;

fcntl(fd, F_SETFL, val);
```

關掉 flag：

```c
val &= ~O_SYNC;
```

---

# 56. `FD_CLOEXEC`

## 現在在學什麼？

一般：

```c
exec(...)
```

不會自動關閉所有 file descriptors。

但是如果：

```text
FD_CLOEXEC = 1
```

則 exec 時：

```text
這個 fd 自動 close
```

這叫：

> close-on-exec

注意：

```text
FD_CLOEXEC
```

是：

> descriptor flag

不是：

> file status flag

---

# 57. `ioctl()`

## 現在在學什麼？

有些 device-specific operation：

> 很難用 `read/write/open` 表達。

所以 UNIX 有：

```c
int ioctl(int fd,
          int request,
          ...);
```

它常被形容成：

> Catchall for I/O operations

例如：

```text
terminal window size
disk control
tape control
socket-specific control
```

所以：

```text
ioctl ≠ 另一種 read
```

而是：

> 一些 device 特殊操作的通用入口。

---

# 58. `/dev/fd`

## 現在在學什麼？

把：

> 已經存在的 file descriptor

包成：

> pathname

例如：

```text
/dev/fd/0
/dev/fd/1
/dev/fd/2
```

概念上：

```c
open("/dev/fd/0", ...)
```

很像：

```c
dup(0)
```

常見：

```text
/dev/stdin
/dev/stdout
/dev/stderr
```

這反映 UNIX 的：

> uniformity

讓只接受 pathname 的工具，也能操作 standard input/output。

---

# 59. 把整章串起來

假設：

```c
int fd =
    open("hello.txt",
         O_RDWR | O_APPEND);
```

Kernel：

```text
1. 找 hello.txt inode
2. 建立 Open File Table Entry
3. flags = O_RDWR | O_APPEND
4. 建立 current offset
5. 在 process FD table 找最低可用 index
6. fd entry 指向 Open File Entry
7. return fd
```

假設：

```text
fd = 3
```

---

再：

```c
write(3, "ABC", 3);
```

Kernel：

```text
fd 3
 ↓
Open File Entry
 ↓
檢查 O_APPEND
 ↓
YES
 ↓
offset = file size
 ↓
write ABC
 ↓
offset += 3
 ↓
必要時更新 file size
```

---

再：

```c
int fd2 = dup(fd);
```

假設：

```text
fd2 = 4
```

結構：

```text
3 ─┐
   ▼
 Open Entry
   ▲
4 ─┘
```

所以：

```c
lseek(3, 0, SEEK_SET);
```

修改的是：

```text
Open Entry.current_offset
```

因此：

```text
fd4 也看到相同 offset
```

---

但是因為：

```text
O_APPEND
```

所以之後：

```c
write(4, "X", 1);
```

仍然會：

```text
offset = EOF
```

再 write。

所以即使你先：

```c
lseek(3, 0, SEEK_SET);
```

也不能讓 append write 去覆蓋檔案開頭。

---

# 60. 字幕常見辨識錯誤對照

老師字幕有不少語音辨識錯誤，可以這樣理解：

```text
System Code
→ System Call

File Discrete
→ File Descriptor

File Discipline
→ 很多地方其實也是 File Descriptor

Open File Discrete Table
→ Open File Descriptor Table

I know
→ inode

L-Sync / L-Seq
→ lseek

Postis
→ POSIX

Reverb Compute
→ Reference Count

Fullbar
→ foobar

Sender Input
→ Standard Input

Sender Output
→ Standard Output
```

---

# 61. CH3 最重要的 8 題

你應該可以不背答案，直接由圖推出：

1. 同一個檔案 `open()` 兩次，兩個 fd 會不會 share current offset？
2. `dup()` 出來的兩個 fd 會不會 share current offset？
3. `fork()` 後 parent / child 的 inherited fd 會不會 share current offset？
4. current file offset 存在哪一層？
5. file size 存在哪一層？
6. Unbuffered I/O 是不是完全沒有 buffer？
7. 為什麼 `lseek(SEEK_END); write()` 不能安全取代 `O_APPEND`？
8. 為什麼 `dup2(fd, 1)` 可以改變 `printf()` 的輸出目的地？

---

# 62. 考試級記憶模型

看到：

```text
fd
```

想到：

```text
per-process descriptor table index
```

---

看到：

```text
open() twice
```

想到：

```text
不同 Open File Table Entry
→ independent offsets
```

---

看到：

```text
dup / fork
```

想到：

```text
shared Open File Table Entry
→ shared offset
```

---

看到：

```text
lseek
```

想到：

```text
只改 current offset
沒有真正 I/O
```

---

看到：

```text
O_APPEND
```

想到：

```text
每次 write 前
atomic 定位 EOF
```

---

看到：

```text
pread / pwrite
```

想到：

```text
positioned I/O
不修改 shared current offset
避免 lseek + I/O race
```

---

看到：

```text
dup2
```

想到：

```text
redirection
newfd → oldfd 的 Open File Entry
```

---

看到：

```text
F_SETFD
```

想到：

```text
descriptor table
只影響該 fd
```

---

看到：

```text
F_SETFL
```

想到：

```text
Open File Table
dup 出來的 fd 一起受到影響
```

---

看到：

```text
fsync
```

想到：

```text
不要只停在 kernel cache
等這個 file 同步到 storage
```

---

# 63. 整章真正要學會的核心

Chapter 3 真正要你掌握的，不是十幾個 API 名字，而是：

```text
File Descriptor
    ↓
Per-process Descriptor Table
    ↓
System Open File Table
    ↓
Current Offset / File Status Flags
    ↓
vnode / inode
    ↓
Buffer / Page Cache
    ↓
Storage
```

然後理解：

- 哪些 state 是 per-process
- 哪些 state 是 shared
- 什麼時候會 share current offset
- 什麼時候會產生 race condition
- 為什麼需要 atomic operation
- 為什麼 buffer size 影響 system call overhead
- 為什麼 write success 不等於 disk persistence
- redirection 為什麼可以只靠 file descriptor 完成

只要這張圖真的理解，CH3 幾乎所有題目都能自己推出來。
