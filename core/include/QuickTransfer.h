#ifndef QUICKTRANSFER_H
#define QUICKTRANSFER_H
void qt_start(const char *config);
void qt_command(const char *command);
void qt_stop(void);
char *qt_poll(void);
void qt_free(char *value);
#endif
