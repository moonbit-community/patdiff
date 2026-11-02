#include <errno.h>
#include <fcntl.h>
#include <moonbit.h>
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

// Reads until end of file, so this works on pipes as well as regular files.
static moonbit_bytes_t read_all_fd(int fd, int32_t *err) {
  size_t capacity = 65536;
  size_t size = 0;
  char *data = malloc(capacity);
  if (data == NULL) {
    err[0] = ENOMEM;
    return moonbit_make_bytes(0, 0);
  }
  for (;;) {
    if (size == capacity) {
      capacity *= 2;
      char *grown = realloc(data, capacity);
      if (grown == NULL) {
        free(data);
        err[0] = ENOMEM;
        return moonbit_make_bytes(0, 0);
      }
      data = grown;
    }
    ssize_t n = read(fd, data + size, capacity - size);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      err[0] = errno;
      free(data);
      return moonbit_make_bytes(0, 0);
    }
    if (n == 0) {
      break;
    }
    size += (size_t)n;
  }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)size, 0);
  memcpy(bytes, data, size);
  free(data);
  return bytes;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t patdiff_read_file(moonbit_bytes_t path,
                                                     int32_t *err) {
  int fd = open((const char *)path, O_RDONLY);
  if (fd < 0) {
    err[0] = errno;
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t bytes = read_all_fd(fd, err);
  close(fd);
  return bytes;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t patdiff_read_stdin(int32_t *err) {
  return read_all_fd(0, err);
}

static int write_all(int fd, const uint8_t *data, size_t size) {
  while (size > 0) {
    ssize_t n = write(fd, data, size);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return errno;
    }
    data += n;
    size -= (size_t)n;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t patdiff_write_fd(int32_t fd, moonbit_bytes_t data) {
  return write_all(fd, data, Moonbit_array_length(data));
}

MOONBIT_FFI_EXPORT int32_t patdiff_write_file(moonbit_bytes_t path,
                                              moonbit_bytes_t data) {
  int fd = open((const char *)path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd < 0) {
    return errno;
  }
  int result = write_all(fd, data, Moonbit_array_length(data));
  close(fd);
  return result;
}

// Gives 0 when the path doesn't exist, 1 for a regular file, 2 for a directory,
// 3 for anything else, and -errno for other errors.
MOONBIT_FFI_EXPORT int32_t patdiff_stat(moonbit_bytes_t path, double *mtime) {
  struct stat st;
  if (stat((const char *)path, &st) != 0) {
    if (errno == ENOENT || errno == ENOTDIR) {
      return 0;
    }
    return -errno;
  }
#if defined(__APPLE__)
  mtime[0] = (double)st.st_mtimespec.tv_sec + (double)st.st_mtimespec.tv_nsec / 1e9;
#else
  mtime[0] = (double)st.st_mtim.tv_sec + (double)st.st_mtim.tv_nsec / 1e9;
#endif
  if (S_ISREG(st.st_mode)) {
    return 1;
  }
  if (S_ISDIR(st.st_mode)) {
    return 2;
  }
  return 3;
}

// The entries of a directory, except "." and "..", each followed by a NUL.
MOONBIT_FFI_EXPORT moonbit_bytes_t patdiff_read_dir(moonbit_bytes_t path,
                                                    int32_t *err) {
  DIR *dir = opendir((const char *)path);
  if (dir == NULL) {
    err[0] = errno;
    return moonbit_make_bytes(0, 0);
  }
  size_t capacity = 4096;
  size_t size = 0;
  char *data = malloc(capacity);
  if (data == NULL) {
    closedir(dir);
    err[0] = ENOMEM;
    return moonbit_make_bytes(0, 0);
  }
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    const char *name = entry->d_name;
    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
      continue;
    }
    size_t len = strlen(name) + 1;
    if (size + len > capacity) {
      capacity = (capacity + len) * 2;
      char *grown = realloc(data, capacity);
      if (grown == NULL) {
        free(data);
        closedir(dir);
        err[0] = ENOMEM;
        return moonbit_make_bytes(0, 0);
      }
      data = grown;
    }
    memcpy(data + size, name, len);
    size += len;
  }
  closedir(dir);
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)size, 0);
  memcpy(bytes, data, size);
  free(data);
  return bytes;
}

// The width of the controlling terminal, or -1 if there isn't one.
MOONBIT_FFI_EXPORT int32_t patdiff_console_width(void) {
  int fd = open("/dev/tty", O_RDONLY);
  if (fd < 0) {
    return -1;
  }
  struct winsize size;
  int result = ioctl(fd, TIOCGWINSZ, &size);
  close(fd);
  if (result != 0 || size.ws_col == 0) {
    return -1;
  }
  return size.ws_col;
}

// Creates a temporary file from `template`, whose name must end in `suffix_len`
// bytes after an XXXXXX, and writes `data` to it. `template` is updated in place.
MOONBIT_FFI_EXPORT int32_t patdiff_temp_file(moonbit_bytes_t template_path,
                                             int32_t suffix_len,
                                             moonbit_bytes_t data) {
  int fd = mkstemps((char *)template_path, suffix_len);
  if (fd < 0) {
    return errno;
  }
  int result = write_all(fd, data, Moonbit_array_length(data));
  close(fd);
  return result;
}

MOONBIT_FFI_EXPORT void patdiff_unlink(moonbit_bytes_t path) {
  unlink((const char *)path);
}

MOONBIT_FFI_EXPORT void patdiff_exit(int32_t code) {
  exit(code);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t patdiff_strerror(int32_t code) {
  const char *message = strerror(code);
  size_t len = strlen(message);
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)len, 0);
  memcpy(bytes, message, len);
  return bytes;
}
