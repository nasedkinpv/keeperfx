/******************************************************************************/
/** @file macos_metal.h
 *  Retina Metal presentation for the macOS build.
 */
/******************************************************************************/

#ifndef DK_MACOS_METAL_H
#define DK_MACOS_METAL_H

#include <SDL2/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

int LbMacOSMetalCreate(SDL_Window *window, int width, int height);
void LbMacOSMetalDestroy(void);
int LbMacOSMetalIsActive(void);
int LbMacOSMetalPresent(const void *pixels, int pitch, const SDL_Color *palette);
void LbMacOSMetalGetDrawableSize(int *width, int *height);

#ifdef __cplusplus
}
#endif

#endif
