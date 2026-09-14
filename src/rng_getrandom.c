#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/random.h>

int randombytes(uint8_t *out, size_t outlen);

int randombytes(uint8_t *out, size_t outlen)
{
  size_t total = 0;
  while (total < outlen) {
    ssize_t got = getrandom(out + total, outlen - total, 0);
    if (got < 0) {
      if (errno == EINTR) continue;
      fprintf(stderr, "pt: getrandom() failed: errno %d\n", errno);
      return -1;
    }
    total += (size_t)got;
  }
  return 0;
}
