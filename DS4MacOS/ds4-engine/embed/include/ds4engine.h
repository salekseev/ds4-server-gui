#ifndef DS4ENGINE_H
#define DS4ENGINE_H

#include <stdint.h>

// ds4_server_main 就是 ds4-server 的 main()，被宏重命名了
// 从 Swift 侧调用：DS4Engine.ds4_server_main(argc, argv)
int ds4_server_main(int argc, char **argv);

// 请求正在运行的 ds4_server_main 优雅退出（等价于发送 SIGINT）
// 线程安全，可从任意线程调用
void ds4_server_request_stop(void);

#endif
