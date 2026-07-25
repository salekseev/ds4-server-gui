#ifndef DS4ENGINE_H
#define DS4ENGINE_H

#include <stdint.h>

// ds4_server_main is ds4-server's main(), renamed via macro.
// Called from Swift as: ds4_server_main(argc, argv)
int ds4_server_main(int argc, char **argv);

// Request a graceful shutdown of a running ds4_server_main (equivalent to
// sending SIGINT, without affecting the rest of the process).
// Thread-safe; may be called from any thread.
void ds4_server_request_stop(void);

#endif
