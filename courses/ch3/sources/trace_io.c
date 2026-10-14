/* POSIX runtime checks for the CH3 teaching examples.
 * Uses a private mkstemp file and unlinks it on completion.
 * Build: cc -std=c11 -Wall -Wextra -Werror trace_io.c -o /tmp/ch3_trace
 */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "copy_fd.h"

static char path[] = "/tmp/ch3_trace_XXXXXX";
static void cleanup(void) { unlink(path); }
static int checked_open(int flags) {
    int fd = open(path, flags);
    if (fd == -1) { perror("open"); exit(1); }
    return fd;
}
static void reset(const char *s) {
    int fd = checked_open(O_WRONLY | O_TRUNC);
    size_t n = strlen(s);
    assert(write(fd, s, n) == (ssize_t)n);
    assert(close(fd) == 0);
}
static char read_one(int fd) {
    char c = 0;
    assert(read(fd, &c, 1) == 1);
    return c;
}
static void contents(const char *expected) {
    int fd = checked_open(O_RDONLY);
    char buf[64] = {0};
    ssize_t n = read(fd, buf, sizeof buf - 1);
    assert(n == (ssize_t)strlen(expected));
    assert(strcmp(buf, expected) == 0);
    assert(close(fd) == 0);
}
int main(void) {
    int temp = mkstemp(path);
    if (temp == -1) { perror("mkstemp"); return 1; }
    atexit(cleanup);
    assert(close(temp) == 0);
    reset("foobar");
    int a = checked_open(O_RDONLY), b = checked_open(O_RDONLY);
    assert(read_one(a) == 'f'); assert(read_one(b) == 'f');
    close(a); close(b); puts("open twice: f, f");

    a = checked_open(O_RDONLY); b = dup(a); assert(b >= 0);
    assert(read_one(a) == 'f'); assert(read_one(b) == 'o');
    close(a); close(b); puts("dup: f, o");

    a = checked_open(O_RDONLY);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) { _exit(read_one(a) == 'f' ? 0 : 1); }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(read_one(a) == 'o'); close(a); puts("fork + wait: parent reads o");

    a = checked_open(O_RDONLY); b = checked_open(O_RDONLY);
    assert(read_one(b) == 'f'); assert(dup2(b, a) == a);
    assert(read_one(a) == 'o'); close(a); close(b); puts("dup2: o");

    fflush(stdout);
    int saved_stdout = dup(STDOUT_FILENO); assert(saved_stdout >= 0);
    a = checked_open(O_WRONLY | O_TRUNC);
    assert(dup2(a, STDOUT_FILENO) == STDOUT_FILENO);
    if (a != STDOUT_FILENO) close(a);
    assert(write(STDOUT_FILENO, "Hi", 2) == 2);
    assert(dup2(saved_stdout, STDOUT_FILENO) == STDOUT_FILENO);
    close(saved_stdout); contents("Hi"); puts("redirection: Hi after closing extra fd");

    for (int append = 0; append <= 1; append++) {
        reset("log");
        a = checked_open(O_WRONLY | (append ? O_APPEND : 0));
        b = checked_open(O_WRONLY | (append ? O_APPEND : 0));
        assert(lseek(a, 0, SEEK_END) == 3);
        assert(lseek(b, 0, SEEK_END) == 3);
        assert(write(b, "B", 1) == 1); assert(write(a, "A", 1) == 1);
        close(a); close(b); contents(append ? "logBA" : "logA");
        puts(append ? "append: logBA" : "seek/write schedule: logA");
    }

    reset("0123456789");
    a = checked_open(O_RDWR);
    struct stat st;
    assert(lseek(a, 16, SEEK_SET) == 16);
    assert(fstat(a, &st) == 0 && st.st_size == 10);
    assert(write(a, "X", 1) == 1);
    assert(fstat(a, &st) == 0 && st.st_size == 17);
    char zero = 1;
    assert(pread(a, &zero, 1, 12) == 1 && zero == 0);
    assert(lseek(a, 0, SEEK_CUR) == 17);
    close(a); puts("seek/hole/pread: size 10 -> 17; zero-filled gap; offset preserved");

    a = checked_open(O_RDWR); b = dup(a); assert(b >= 0);
    int c = checked_open(O_RDWR);
    assert(fcntl(a, F_SETFD, FD_CLOEXEC) == 0);
    assert(fcntl(a, F_GETFD) & FD_CLOEXEC);
    assert(!(fcntl(b, F_GETFD) & FD_CLOEXEC));
    int flags = fcntl(a, F_GETFL); assert(flags >= 0);
    assert(fcntl(a, F_SETFL, flags | O_APPEND) == 0);
    assert(fcntl(b, F_GETFL) & O_APPEND);
    assert(!(fcntl(c, F_GETFL) & O_APPEND));
    close(a); close(b); close(c); puts("fcntl: FD local; FL shared by dup only");

    int pipefd[2]; assert(pipe(pipefd) == 0);
    errno = 0;
    assert(lseek(pipefd[0], 0, SEEK_CUR) == (off_t)-1 && errno == ESPIPE);
    close(pipefd[0]); close(pipefd[1]); puts("pipe lseek: ESPIPE");

    reset("copy test: foobar\n");
    a = checked_open(O_RDONLY);
    FILE *out = tmpfile(); assert(out != NULL);
    assert(copy_fd(a, fileno(out)) == 0);
    assert(lseek(fileno(out), 0, SEEK_SET) == 0);
    char buf[32] = {0};
    assert(read(fileno(out), buf, sizeof buf) == 18);
    assert(strcmp(buf, "copy test: foobar\n") == 0);
    close(a); fclose(out); puts("copy_fd: real file copy succeeded");
    puts("All runtime checks passed.");
    return 0;
}
