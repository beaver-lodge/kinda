#include <mruby.h>
#include <stdlib.h>

typedef struct kinda_mruby_allocator {
  size_t allocation_calls;
  size_t live_bytes;
  size_t peak_bytes;
  size_t fail_after;
  size_t failure_count;
} kinda_mruby_allocator;

struct kinda_mruby_allocation_header {
  kinda_mruby_allocator *owner;
  size_t size;
};

#if defined(_MSC_VER)
#define KINDA_THREAD_LOCAL __declspec(thread)
#else
#define KINDA_THREAD_LOCAL _Thread_local
#endif

static KINDA_THREAD_LOCAL kinda_mruby_allocator *kinda_mruby_current_allocator;

void *mrb_basic_alloc_func(void *pointer, size_t size) {
  struct kinda_mruby_allocation_header *header =
    pointer == NULL ? NULL : ((struct kinda_mruby_allocation_header *)pointer - 1);
  kinda_mruby_allocator *owner = header == NULL ? kinda_mruby_current_allocator : header->owner;
  size_t previous_size = header == NULL ? 0 : header->size;

  if (size == 0) {
    if (owner != NULL) owner->live_bytes -= previous_size;
    free(header);
    return NULL;
  }

  if (owner != NULL) {
    owner->allocation_calls++;
    if (owner->fail_after != 0 && owner->allocation_calls > owner->fail_after) {
      owner->failure_count++;
      return NULL;
    }
  }

  struct kinda_mruby_allocation_header *resized = realloc(header, sizeof(*resized) + size);
  if (resized == NULL) return NULL;
  resized->owner = owner;
  resized->size = size;

  if (owner != NULL) {
    owner->live_bytes = owner->live_bytes - previous_size + size;
    if (owner->live_bytes > owner->peak_bytes) owner->peak_bytes = owner->live_bytes;
  }
  return resized + 1;
}

void kinda_mruby_allocator_init(kinda_mruby_allocator *allocator) {
  allocator->allocation_calls = 0;
  allocator->live_bytes = 0;
  allocator->peak_bytes = 0;
  allocator->fail_after = 0;
  allocator->failure_count = 0;
}

void kinda_mruby_allocator_set_budget(kinda_mruby_allocator *allocator, size_t additional_allocations) {
  allocator->fail_after = allocator->allocation_calls + additional_allocations;
}

kinda_mruby_allocator *kinda_mruby_allocator_enter(kinda_mruby_allocator *allocator) {
  kinda_mruby_allocator *previous = kinda_mruby_current_allocator;
  kinda_mruby_current_allocator = allocator;
  return previous;
}

void kinda_mruby_allocator_leave(kinda_mruby_allocator *previous) {
  kinda_mruby_current_allocator = previous;
}

mrb_state *kinda_mruby_open(kinda_mruby_allocator *allocator) {
  kinda_mruby_allocator *previous = kinda_mruby_allocator_enter(allocator);
  mrb_state *state = mrb_open();
  kinda_mruby_allocator_leave(previous);
  return state;
}
