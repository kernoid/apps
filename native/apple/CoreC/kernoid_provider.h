// SPDX-License-Identifier: MIT
// The C boundary of the file shells' core (rust/src/provider.rs): a request in JSON, an answer in JSON – to be given
// back to kernoid_provider_free. Linked from rust/'s static library (native/apple/build-rust.sh).
#ifndef KERNOID_PROVIDER_H
#define KERNOID_PROVIDER_H

char *kernoid_provider_call(const char *request);
void kernoid_provider_free(char *answer);

#endif
