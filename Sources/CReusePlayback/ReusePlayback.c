// SPDX-License-Identifier: Apache-2.0
#include "ReusePlayback.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

enum { RABPlaying = 1, RABProcessed = 2 };
struct RABState {
    float *before;
    float *after;
    uint32_t count, fadeFrames;
    atomic_uint flags, publishedPosition;
    // The following fields belong exclusively to the render thread.
    uint32_t cursor, remaining;
    float mix, target, step;
};

RABState *RABCreate(const float *before, const float *after, uint32_t count, uint32_t fadeFrames) {
    if (!before || !after || count == 0) return NULL;
    RABState *state = calloc(1, sizeof(*state));
    if (!state) return NULL;
    atomic_init(&state->flags, RABProcessed);
    atomic_init(&state->publishedPosition, 0);
    // Never allow an implementation that hides a mutex inside a render atomic.
    if (!atomic_is_lock_free(&state->flags) || !atomic_is_lock_free(&state->publishedPosition)) {
        free(state); return NULL;
    }
    state->before = malloc((size_t)count * sizeof(float));
    state->after = malloc((size_t)count * sizeof(float));
    if (!state->before || !state->after) { RABDestroy(state); return NULL; }
    memcpy(state->before, before, (size_t)count * sizeof(float));
    memcpy(state->after, after, (size_t)count * sizeof(float));
    state->count = count;
    state->fadeFrames = fadeFrames > 0 ? fadeFrames : 1;
    state->mix = state->target = 1;
    return state;
}

void RABDestroy(RABState *state) {
    if (!state) return;
    free(state->before); free(state->after); free(state);
}

void RABSetProcessed(RABState *state, bool processed) {
    if (processed) atomic_fetch_or_explicit(&state->flags, RABProcessed, memory_order_relaxed);
    else atomic_fetch_and_explicit(&state->flags, ~RABProcessed, memory_order_relaxed);
}

void RABSetPlaying(RABState *state, bool playing) {
    if (playing) atomic_fetch_or_explicit(&state->flags, RABPlaying, memory_order_relaxed);
    else atomic_fetch_and_explicit(&state->flags, ~RABPlaying, memory_order_relaxed);
}

bool RABIsProcessed(const RABState *state) {
    return (atomic_load_explicit(&state->flags, memory_order_relaxed) & RABProcessed) != 0;
}

bool RABIsPlaying(const RABState *state) {
    return (atomic_load_explicit(&state->flags, memory_order_relaxed) & RABPlaying) != 0;
}

uint32_t RABPosition(const RABState *state) {
    return atomic_load_explicit(&state->publishedPosition, memory_order_relaxed);
}

uint32_t RABRender(RABState *state, float *output, uint32_t frames) {
    const unsigned flags = atomic_load_explicit(&state->flags, memory_order_relaxed);
    const float target = (flags & RABProcessed) ? 1 : 0;
    memset(output, 0, (size_t)frames * sizeof(float));
    if (!(flags & RABPlaying)) {
        state->mix = state->target = target;
        state->remaining = 0;
        return 0;
    }
    if (state->cursor >= state->count) state->cursor = 0; // Play again after EOF.
    if (state->cursor == 0) { state->mix = state->target = target; state->remaining = 0; }
    if (target != state->target) {
        state->target = target;
        state->remaining = state->fadeFrames;
        state->step = (target - state->mix) / state->fadeFrames;
    }
    uint32_t available = state->count - state->cursor;
    uint32_t rendered = frames < available ? frames : available;
    for (uint32_t i = 0; i < rendered; ++i) {
        if (state->remaining > 0) {
            state->mix += state->step;
            if (--state->remaining == 0) state->mix = state->target;
        }
        uint32_t position = state->cursor++;
        float mix = state->mix;
        // Preserve exact samples outside the transition. Linear crossfade avoids
        // the loudness boost of an equal-power fade between correlated signals.
        output[i] = mix == 0 ? state->before[position] : mix == 1 ? state->after[position]
            : state->before[position] * (1 - mix) + state->after[position] * mix;
    }
    atomic_store_explicit(&state->publishedPosition, state->cursor, memory_order_relaxed);
    if (state->cursor == state->count) RABSetPlaying(state, false);
    return rendered;
}
