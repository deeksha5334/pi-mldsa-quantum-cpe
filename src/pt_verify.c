#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mldsa_native.h>
#include "pt_common.h"

#define PK_BYTES  MLDSA_PUBLICKEYBYTES(MLD_CONFIG_PARAMETER_SET)
#define SIG_BYTES MLDSA_BYTES(MLD_CONFIG_PARAMETER_SET)

/* Anti-rollback floor. Bump this (and re-sign boot.img) when an old image
   must no longer be accepted. Production: back this with an OTP/TPM counter
   (gated on OTP burn, deferred). */
#define PT_MIN_FW_VERSION 1

/* Value of the "# firmware-version:" manifest line, or -1 if absent/bad.
   Raw-buffer scan: no NUL assumption, no GNU/libc extensions, so it behaves
   identically under klibc on the card and glibc on the bench. */
static long pt_manifest_version(const uint8_t *buf, size_t len)
{
  const char *key = "# firmware-version:";
  size_t klen = strlen(key);
  for (size_t i = 0; i + klen <= len; i++) {
    if (i != 0 && buf[i-1] != '\n') continue;   /* start of line only */
    if (memcmp(buf + i, key, klen) != 0) continue;
    size_t j = i + klen;
    while (j < len && (buf[j] == ' ' || buf[j] == '\t')) j++;
    long v = 0; int got = 0;
    while (j < len && buf[j] >= '0' && buf[j] <= '9') { v = v*10 + (buf[j]-'0'); got = 1; j++; }
    return got ? v : -1;
  }
  return -1;
}

int main(int argc, char **argv)
{
  uint8_t pk[PK_BYTES];
  uint8_t sig[SIG_BYTES];
  uint8_t *msg = NULL;
  size_t msg_len = 0;
  int rc = 1;

  /* Unbuffered stdout: when the boot script captures stdout+stderr together,
     lines must appear in the order they happen (signature result before any
     rollback verdict), not in buffer-flush order. */
  (void)setvbuf(stdout, NULL, _IONBF, 0);

  if (argc != 4) {
    fprintf(stderr, "usage: %s <manifest> <sig> <key.pk>\n", argv[0]);
    return 2;
  }

  msg = pt_read_file(argv[1], &msg_len);
  if (msg == NULL) goto out;
  if (pt_read_exact(argv[2], sig, SIG_BYTES) != 0) goto out;
  if (pt_read_exact(argv[3], pk, PK_BYTES) != 0) goto out;

  volatile int v1 = -1, v2 = -1;
  v1 = mldsa_verify(sig, msg, msg_len,
                    (const uint8_t *)PT_CONTEXT, PT_CONTEXT_LEN, pk);
  v2 = mldsa_verify(sig, msg, msg_len,
                    (const uint8_t *)PT_CONTEXT, PT_CONTEXT_LEN, pk);
  if (v1 != 0 || v2 != 0 || v1 != v2) {
    fprintf(stderr, "SIGNATURE INVALID\n");
    fprintf(stderr, "  manifest: %s\n", argv[1]);
    goto out;
  }

  printf("SIGNATURE VALID\n");
  printf("  manifest : %s (%zu bytes)\n", argv[1], msg_len);
  printf("  algorithm: ML-DSA-%d\n", MLD_CONFIG_PARAMETER_SET);
  printf("  context  : \"%s\"\n", PT_CONTEXT);

  /* Anti-rollback: only trusted AFTER the signature verifies. */
  long ver = pt_manifest_version(msg, msg_len);
  if (ver < 0) {
    fprintf(stderr, "ROLLBACK CHECK FAILED: no firmware-version in manifest\n");
    goto out;
  }
  if (ver < PT_MIN_FW_VERSION) {
    fprintf(stderr, "ROLLBACK REJECTED: version %ld < floor %d\n", ver, PT_MIN_FW_VERSION);
    goto out;
  }
  printf("  fw-version: %ld (floor %d)\n", ver, PT_MIN_FW_VERSION);

  if (v1 == 0 && v2 == 0) { printf("PT_VERIFY_OK_A5C3\n"); rc = 0; }

out:
  free(msg);
  return rc;
}
