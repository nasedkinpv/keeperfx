/******************************************************************************/
/** @file macos_metal.h
 *  Small macOS-specific adjustments for SDL's Metal presentation layer.
 */
/******************************************************************************/

#ifndef DK_MACOS_METAL_H
#define DK_MACOS_METAL_H

#include <SDL2/SDL_render.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Marks SDL's Metal layer as opaque, colour-managed sRGB content.
 *
 * @return Non-zero when the renderer is Metal and the layer was configured.
 */
int LbMacOSConfigureMetalLayer(SDL_Renderer *renderer);

#ifdef __cplusplus
}
#endif

#endif
