/******************************************************************************/
/** @file macos_metal.m
 *  Native presentation configuration for macOS.
 */
/******************************************************************************/

#include "macos_metal.h"

#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/CAMetalLayer.h>

#include <string.h>

int LbMacOSConfigureMetalLayer(SDL_Renderer *renderer)
{
    SDL_RendererInfo renderer_info = {0};
    if ((renderer == NULL) || (SDL_GetRendererInfo(renderer, &renderer_info) != 0) ||
        (renderer_info.name == NULL) || (strcmp(renderer_info.name, "metal") != 0)) {
        return 0;
    }

    CAMetalLayer *layer = (CAMetalLayer *)SDL_RenderGetMetalLayer(renderer);
    if (layer == nil) {
        return 0;
    }

    CGColorSpaceRef colour_space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colour_space == NULL) {
        return 0;
    }

    layer.opaque = YES;
    layer.colorspace = colour_space;
    CGColorSpaceRelease(colour_space);
    return 1;
}
