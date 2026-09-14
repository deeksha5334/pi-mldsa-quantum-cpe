#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mldsa_native.h>
#include "pt_common.h"

#define SK_BYTES  MLDSA_SECRETKEYBYTES(MLD_CONFIG_PARAMETER_SET)
#define SIG_BYTES MLDSA_BYTES(MLD_CONFIG_PARAMETER_SET)

int main(int argc, char **argv)
{
  uint8_t sk[SK_BYTES];
  uint8_t sig[SIG_BYTES];
  uint8_t *msg = NULL;
  size_t msg_len = 0;
  int rc = 1;

  if (argc != 4) {
    fprintf(stderr, "usage: %s <manifest> <key.sk> <out.sig>\n", argv[0]);
    return 2;
  }

  msg = pt_read_file(argv[1], &msg_len);
  if (msg == NULL) goto out;
  if (msg_len == 0) { fprintf(stderr, "pt-sign: %s is empty\n", argv[1]); goto out; }
  if (pt_read_exact(argv[2], sk, SK_BYTES) != 0) goto out;

  printf("pt-sign: ML-DSA-%d\n", MLD_CONFIG_PARAMETER_SET);
  printf("  manifest : %s (%zu bytes)\n", argv[1], msg_len);
  printf("  context  : \"%s\"\n", PT_CONTEXT);

  if (mldsa_signature(sig, msg, msg_len,
                      (const uint8_t *)PT_CONTEXT, PT_CONTEXT_LEN, sk) != 0) {
    fprintf(stderr, "pt-sign: mldsa_signature failed\n");
    goto out;
  }
  if (pt_write_file(argv[3], sig, SIG_BYTES, 0644) != 0) goto out;

  printf("\nwrote %s (%zu bytes)\n", argv[3], (size_t)SIG_BYTES);
  rc = 0;

out:
  memset(sk, 0, sizeof(sk));
  free(msg);
  return rc;
}
