#include "sqlite_bridge.h"

int kinda_sqlite_bind_text_transient(sqlite3_stmt *statement, int index,
                                     const char *value, int length) {
  return sqlite3_bind_text(statement, index, value, length, SQLITE_TRANSIENT);
}

int kinda_sqlite_bind_blob_transient(sqlite3_stmt *statement, int index,
                                     const void *value, int length) {
  return sqlite3_bind_blob(statement, index, value, length, SQLITE_TRANSIENT);
}
