// Copyright 2025, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { getEnv } from "./getenv";
import { lazy } from "./util";

// REBRAND: "WAVETERM_DEV" → "TERMINOLGY_DEV", "WAVETERM_DEV_VITE" → "TERMINOLGY_DEV_VITE"
export const WaveDevVarName = "TERMINOLGY_DEV";
export const WaveDevViteVarName = "TERMINOLGY_DEV_VITE";

/**
 * Determines whether the current app instance is a development build.
 * @returns True if the current app instance is a development build.
 */
export const isDev = lazy(() => !!getEnv(WaveDevVarName));

/**
 * Determines whether the current app instance is running via the Vite dev server.
 * @returns True if the app is running via the Vite dev server.
 */
export const isDevVite = lazy(() => !!getEnv(WaveDevViteVarName));
