#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mldsa_native.h>
#include "pt_common.h"

#define PK_BYTES  MLDSA_PUBLICKEYBYTES(MLD_CONFIG_PARAMETER_SET)
#define SIG_BYTES MLDSA_BYTES(MLD_CONFIG_PARAMETER_SET)

int main(int argc, char **argv)
{
  uint8_t pk[PK_BYTES];
  uint8_t sig[SIG_BYTES];
  uint8_t *msg = NULL;
  size_t msg_len = 0;
  int rc = 1;

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
  if (v1 == 0 && v2 == 0) { printf("PT_VERIFY_OK_A5C3\n"); rc = 0; }

out:
  free(msg);
  return rc;
}
