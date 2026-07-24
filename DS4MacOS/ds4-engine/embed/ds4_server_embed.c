/* Embed wrapper: compiles pristine upstream ds4_server.c into the app.
 *
 * - Renames the server's main() so the GUI can call it in-process.
 * - DS4_SERVER_TEST_NO_MAIN drops the unit-test main() at the bottom of
 *   ds4_server.c (defensive; only relevant if DS4_SERVER_TEST is ever defined).
 * - ds4_server_request_stop() lives in this translation unit so it can reach
 *   the file-static g_stop_requested / g_listen_fd. */
#define main ds4_server_main
#ifndef DS4_SERVER_TEST_NO_MAIN /* both build systems also define it globally as =1 */
#define DS4_SERVER_TEST_NO_MAIN 1
#endif
#include "ds4_server.c"
#undef main

void ds4_server_request_stop(void) {
    g_stop_requested = 1;
    if (g_listen_fd >= 0) {
        int fd = (int)g_listen_fd;
        g_listen_fd = -1;
        close(fd);
    }
}
