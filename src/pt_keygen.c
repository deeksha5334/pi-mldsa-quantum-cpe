#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mldsa_native.h>
#include "pt_common.h"

#define PK_BYTES MLDSA_PUBLICKEYBYTES(MLD_CONFIG_PARAMETER_SET)
#define SK_BYTES MLDSA_SECRETKEYBYTES(MLD_CONFIG_PARAMETER_SET)

int main(int argc, char **argv)
{
  uint8_t pk[PK_BYTES];
  uint8_t sk[SK_BYTES];
  char pk_path[512], sk_path[512];
  int rc = 1;

  if (argc != 2) { fprintf(stderr, "usage: %s <name>\n", argv[0]); return 2; }

  snprintf(pk_path, sizeof(pk_path), "%s.pk", argv[1]);
  snprintf(sk_path, sizeof(sk_path), "%s.sk", argv[1]);

  printf("pt-keygen: ML-DSA-%d\n", MLD_CONFIG_PARAMETER_SET);
  printf("  public key : %zu bytes\n", (size_t)PK_BYTES);
  printf("  secret key : %zu bytes\n", (size_t)SK_BYTES);

  if (mldsa_keypair(pk, sk) != 0) {
    fprintf(stderr, "pt-keygen: mldsa_keypair failed\n");
    goto out;
  }
  if (pt_write_file(sk_path, sk, SK_BYTES, 0600) != 0) goto out;
  if (pt_write_file(pk_path, pk, PK_BYTES, 0644) != 0) goto out;

  printf("\nwrote %s (0600)\nwrote %s (0644)\n", sk_path, pk_path);
  printf("public key, first 16 bytes: ");
  pt_print_hex(pk, 16);
  printf("\nSecret key stays on this host. Do not copy it to a device.\n");
  rc = 0;

out:
  memset(sk, 0, sizeof(sk));
  return rc;
}
