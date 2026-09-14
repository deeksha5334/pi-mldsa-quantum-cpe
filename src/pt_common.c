#include "pt_common.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

uint8_t *pt_read_file(const char *path, size_t *out_len)
{
  FILE *f = fopen(path, "rb");
  long sz;
  uint8_t *buf;
  size_t got;

  if (f == NULL) { fprintf(stderr, "pt: cannot open %s: %s\n", path, strerror(errno)); return NULL; }
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
  sz = ftell(f);
  if (sz < 0) { fclose(f); return NULL; }
  rewind(f);

  buf = malloc((size_t)sz + 1);
  if (buf == NULL) { fclose(f); return NULL; }

  got = fread(buf, 1, (size_t)sz, f);
  fclose(f);
  if (got != (size_t)sz) { free(buf); return NULL; }

  buf[sz] = 0;
  *out_len = (size_t)sz;
  return buf;
}

int pt_read_exact(const char *path, uint8_t *buf, size_t expect_len)
{
  size_t len;
  uint8_t *tmp = pt_read_file(path, &len);
  if (tmp == NULL) return -1;
  if (len != expect_len) {
    fprintf(stderr, "pt: %s is %zu bytes, expected %zu\n", path, len, expect_len);
    free(tmp); return -1;
  }
  memcpy(buf, tmp, expect_len);
  free(tmp);
  return 0;
}

int pt_write_file(const char *path, const uint8_t *buf, size_t len, int mode)
{
  ssize_t w;
  size_t total = 0;
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, (mode_t)mode);

  if (fd < 0) {
    fprintf(stderr, "pt: cannot create %s: %s\n", path, strerror(errno));
    return -1;
  }
  while (total < len) {
    w = write(fd, buf + total, len - total);
    if (w <= 0) { close(fd); return -1; }
    total += (size_t)w;
  }
  return close(fd) == 0 ? 0 : -1;
}

void pt_print_hex(const uint8_t *buf, size_t len)
{
  size_t i;
  for (i = 0; i < len; i++) printf("%02x", buf[i]);
  printf("\n");
}
