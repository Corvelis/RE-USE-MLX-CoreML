// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct RABState RABState;

// Copies both immutable mono buffers. Only one render thread may call RABRender;
// control/status functions are lock-free and may run concurrently with rendering.
RABState * _Nullable RABCreate(const float * _Nonnull before, const float * _Nonnull after, uint32_t count,
                    uint32_t fadeFrames);
void RABDestroy(RABState * _Nullable state);
void RABSetProcessed(RABState * _Nonnull state, bool processed);
void RABSetPlaying(RABState * _Nonnull state, bool playing);
bool RABIsProcessed(const RABState * _Nonnull state);
bool RABIsPlaying(const RABState * _Nonnull state);
uint32_t RABPosition(const RABState * _Nonnull state);
uint32_t RABRender(RABState * _Nonnull state, float * _Nonnull output, uint32_t frames);
