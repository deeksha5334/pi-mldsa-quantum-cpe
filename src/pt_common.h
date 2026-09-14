#ifndef PT_COMMON_H
#define PT_COMMON_H

#include <stddef.h>
#include <stdint.h>

#define PT_CONTEXT "pi-trust-manifest-v1"
#define PT_CONTEXT_LEN (sizeof(PT_CONTEXT) - 1)

uint8_t *pt_read_file(const char *path, size_t *out_len);
int pt_read_exact(const char *path, uint8_t *buf, size_t expect_len);
int pt_write_file(const char *path, const uint8_t *buf, size_t len, int mode);
void pt_print_hex(const uint8_t *buf, size_t len);

#endif
