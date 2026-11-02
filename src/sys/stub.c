#include <fcntl.h>
#include <moonbit.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <unistd.h>

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
