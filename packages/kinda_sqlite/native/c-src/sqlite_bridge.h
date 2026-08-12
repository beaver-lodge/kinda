#ifndef KINDA_SQLITE_BRIDGE_H
#define KINDA_SQLITE_BRIDGE_H

#include "sqlite3.h"

int kinda_sqlite_bind_text_transient(sqlite3_stmt *statement, int index,
                                     const char *value, int length);

#endif
