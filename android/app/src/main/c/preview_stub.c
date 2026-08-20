// Empty native library used only by the Android UI preview target. Desktop
// native APIs are not exercised by the preview screen.
void remote_storage_preview_stub(void) {}

// Signature expected by irondash_message_channel. Returning zero is sufficient
// for the preview because no native drag/drop operation is exercised.
#include <stdint.h>
int64_t super_native_extensions_init_message_channel_context(void *context) {
  (void)context;
  return 0;
}
