#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>

int ada_quality_restore_sigpipe_default(void)
{
    struct sigaction action;

    memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_DFL;
    if (sigemptyset(&action.sa_mask) != 0) {
        return -1;
    }
    return sigaction(SIGPIPE, &action, NULL);
}

static int close_on_exec(int descriptor)
{
    if (descriptor >= 0) {
        int flags = fcntl(descriptor, F_GETFD);
        if (flags < 0 || fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) < 0) {
            close(descriptor);
            return -1;
        }
    }
    return descriptor;
}

int ada_quality_open_read_nofollow(const char *path)
{
    return close_on_exec(open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW));
}

int ada_quality_open_child_nofollow(int directory_fd, const char *name)
{
    return close_on_exec(openat(directory_fd, name,
                                O_RDONLY | O_NONBLOCK | O_NOFOLLOW));
}

int ada_quality_create_private(const char *path)
{
    return close_on_exec(open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                              S_IRUSR | S_IWUSR));
}

int ada_quality_create_public(const char *path)
{
    return close_on_exec(open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                              S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH));
}

int ada_quality_create_public_at(int directory_fd, const char *name)
{
    return close_on_exec(openat(directory_fd, name,
                                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH));
}

int ada_quality_open_directory_nofollow(const char *path)
{
    int descriptor = close_on_exec(open(path, O_RDONLY | O_NOFOLLOW));
    struct stat status;

    if (descriptor >= 0 &&
        (fstat(descriptor, &status) != 0 || !S_ISDIR(status.st_mode))) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

int ada_quality_try_lock_file(const char *path)
{
    int descriptor = close_on_exec
        (open(path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR));

    if (descriptor < 0) {
        return -1;
    }
    if (flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

int ada_quality_descriptor_kind(int descriptor)
{
    struct stat status;

    if (fstat(descriptor, &status) != 0) {
        return -1;
    }
    if (S_ISREG(status.st_mode)) {
        return 1;
    }
    if (S_ISDIR(status.st_mode)) {
        return 2;
    }
    return 0;
}

void *ada_quality_directory_open(int descriptor)
{
    int duplicate = close_on_exec(openat(descriptor, ".", O_RDONLY | O_NOFOLLOW));

    if (duplicate < 0) {
        return NULL;
    }
    DIR *directory = fdopendir(duplicate);
    if (directory == NULL) {
        close(duplicate);
    }
    return directory;
}

int ada_quality_directory_next(void *handle, char *name, size_t capacity)
{
    DIR *directory = handle;
    struct dirent *entry;
    size_t length;

    if (directory == NULL || name == NULL || capacity == 0) {
        errno = EINVAL;
        return -1;
    }
    errno = 0;
    entry = readdir(directory);
    if (entry == NULL) {
        return errno == 0 ? 0 : -1;
    }
    length = strlen(entry->d_name);
    if (length + 1 > capacity) {
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(name, entry->d_name, length + 1);
    return 1;
}

int ada_quality_directory_close(void *handle)
{
    return handle == NULL ? 0 : closedir(handle);
}
