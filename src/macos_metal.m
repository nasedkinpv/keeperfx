/******************************************************************************/
/** @file macos_metal.m
 *  Native Retina presentation for KeeperFX's 8-bit framebuffer.
 */
/******************************************************************************/

#include "macos_metal.h"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <math.h>
#include <stdint.h>
#include <string.h>

#define KFX_METAL_FRAMES_IN_FLIGHT 3

typedef struct KfxMetalPaletteEntry {
    float r;
    float g;
    float b;
    float a;
} KfxMetalPaletteEntry;

typedef struct KfxMetalPostProcess {
    float sharpness;
    float dither;
} KfxMetalPostProcess;

static struct {
    SDL_Window *window;
    SDL_MetalView view;
    CAMetalLayer *layer;
    id<MTLDevice> device;
    id<MTLCommandQueue> command_queue;
    id<MTLRenderPipelineState> pipeline;
    id<MTLTexture> index_textures[KFX_METAL_FRAMES_IN_FLIGHT];
    id<MTLBuffer> palette_buffers[KFX_METAL_FRAMES_IN_FLIGHT];
    int width;
    int height;
    unsigned int frame_index;
    float saturation;
    float contrast;
    KfxMetalPostProcess post_process;
} kfx_metal;

static const char *kfx_metal_shader_source =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VertexOut { float4 position [[position]]; float2 texcoord; };\n"
    "vertex VertexOut kfx_vertex(uint vertex_id [[vertex_id]]) {\n"
    "  const float2 positions[] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };\n"
    "  const float2 texcoords[] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };\n"
    "  return { float4(positions[vertex_id], 0.0, 1.0), texcoords[vertex_id] };\n"
    "}\n"
    "struct PostProcess { float sharpness; float dither; };\n"
    "inline float3 kfx_colour(texture2d<uint, access::read> indices,\n"
    "    constant float4 *palette, int2 pixel, uint2 size) {\n"
    "  const int2 clipped = clamp(pixel, int2(0), int2(size) - 1);\n"
    "  return palette[indices.read(uint2(clipped)).r].rgb;\n"
    "}\n"
    "inline float kfx_luma(float3 colour) {\n"
    "  return dot(colour, float3(0.2126, 0.7152, 0.0722));\n"
    "}\n"
    "fragment float4 kfx_fragment(VertexOut in [[stage_in]],\n"
    "    texture2d<uint, access::read> indices [[texture(0)]],\n"
    "    constant float4 *palette [[buffer(0)]],\n"
    "    constant PostProcess &post [[buffer(1)]]) {\n"
    "  const uint2 size(indices.get_width(), indices.get_height());\n"
    "  const uint2 pixel = min(uint2(in.texcoord * float2(size)), size - 1);\n"
    "  const int2 p = int2(pixel);\n"
    "  const float3 centre = kfx_colour(indices, palette, p, size);\n"
    "  const float3 left = kfx_colour(indices, palette, p + int2(-1, 0), size);\n"
    "  const float3 right = kfx_colour(indices, palette, p + int2(1, 0), size);\n"
    "  const float3 up = kfx_colour(indices, palette, p + int2(0, -1), size);\n"
    "  const float3 down = kfx_colour(indices, palette, p + int2(0, 1), size);\n"
    "  const float3 average = (left + right + up + down) * 0.25;\n"
    "  const float centre_luma = kfx_luma(centre);\n"
    "  float darkest = min(min(kfx_luma(left), kfx_luma(right)),\n"
    "      min(kfx_luma(up), kfx_luma(down)));\n"
    "  float lightest = max(max(kfx_luma(left), kfx_luma(right)),\n"
    "      max(kfx_luma(up), kfx_luma(down)));\n"
    "  darkest = min(darkest, centre_luma);\n"
    "  lightest = max(lightest, centre_luma);\n"
    "  const float local_range = lightest - darkest;\n"
    "  const float edge_mask = smoothstep(0.01, 0.08, local_range) *\n"
    "      (1.0 - smoothstep(0.35, 0.65, local_range));\n"
    "  float3 colour = saturate(centre + (centre - average) * post.sharpness * edge_mask);\n"
    "  const float noise = fract(52.9829189 * fract(dot(float2(pixel),\n"
    "      float2(0.06711056, 0.00583715)))) - 0.5;\n"
    "  // Approximate the linear-light size of one encoded sRGB step.\n"
    "  const float3 srgb_step = max(float3(1.0 / 12.92),\n"
    "      (2.4 / 1.055) * sqrt(max(colour, float3(0.0))));\n"
    "  colour += noise * (post.dither / 255.0) * srgb_step;\n"
    "  return float4(saturate(colour), 1.0);\n"
    "}\n";

static float kfx_metal_preference(NSString *key, float fallback, float minimum, float maximum)
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    float result = (value != nil) ? [value floatValue] : fallback;
    return fminf(fmaxf(result, minimum), maximum);
}

static float kfx_srgb_to_linear(uint8_t component)
{
    // KeeperFX expands its 6-bit VGA palette to 0..252. Map that full DAC
    // range to 0..1 before entering the linear-light Metal pipeline.
    const float encoded = fminf((float)component / 252.0f, 1.0f);
    if (encoded <= 0.04045f) {
        return encoded / 12.92f;
    }
    return powf((encoded + 0.055f) / 1.055f, 2.4f);
}

static void kfx_metal_update_palette(KfxMetalPaletteEntry *destination,
    const SDL_Color *palette)
{
    for (int i = 0; i < 256; i++) {
        float r = kfx_srgb_to_linear(palette[i].r);
        float g = kfx_srgb_to_linear(palette[i].g);
        float b = kfx_srgb_to_linear(palette[i].b);
        const float luminance = r * 0.2126f + g * 0.7152f + b * 0.0722f;
        r = luminance + (r - luminance) * kfx_metal.saturation;
        g = luminance + (g - luminance) * kfx_metal.saturation;
        b = luminance + (b - luminance) * kfx_metal.saturation;
        destination[i].r = fminf(fmaxf((r - 0.18f) * kfx_metal.contrast + 0.18f, 0.0f), 1.0f);
        destination[i].g = fminf(fmaxf((g - 0.18f) * kfx_metal.contrast + 0.18f, 0.0f), 1.0f);
        destination[i].b = fminf(fmaxf((b - 0.18f) * kfx_metal.contrast + 0.18f, 0.0f), 1.0f);
        destination[i].a = 1.0f;
    }
}

void LbMacOSMetalDestroy(void)
{
    for (int i = 0; i < KFX_METAL_FRAMES_IN_FLIGHT; i++) {
        [kfx_metal.index_textures[i] release];
        [kfx_metal.palette_buffers[i] release];
    }
    [kfx_metal.pipeline release];
    [kfx_metal.command_queue release];
    [kfx_metal.device release];
    if (kfx_metal.view != NULL) {
        SDL_Metal_DestroyView(kfx_metal.view);
    }
    memset(&kfx_metal, 0, sizeof(kfx_metal));
}

int LbMacOSMetalCreate(SDL_Window *window, int width, int height)
{
    @autoreleasepool {
        LbMacOSMetalDestroy();

        kfx_metal.window = window;
        kfx_metal.width = width;
        kfx_metal.height = height;
        kfx_metal.saturation = kfx_metal_preference(@"MetalSaturation", 1.0f, 0.0f, 2.0f);
        kfx_metal.contrast = kfx_metal_preference(@"MetalContrast", 1.0f, 0.5f, 2.0f);
        kfx_metal.post_process.sharpness = kfx_metal_preference(@"MetalSharpness", 0.08f, 0.0f, 1.0f);
        kfx_metal.post_process.dither = kfx_metal_preference(@"MetalDither", 0.75f, 0.0f, 2.0f);
        kfx_metal.view = SDL_Metal_CreateView(window);
        if (kfx_metal.view == NULL) {
            LbMacOSMetalDestroy();
            return 0;
        }
        kfx_metal.layer = (CAMetalLayer *)SDL_Metal_GetLayer(kfx_metal.view);
        kfx_metal.device = [MTLCreateSystemDefaultDevice() retain];
        if ((kfx_metal.layer == nil) || (kfx_metal.device == nil)) {
            SDL_SetError("Metal device or layer is unavailable");
            LbMacOSMetalDestroy();
            return 0;
        }

        kfx_metal.layer.device = kfx_metal.device;
        // The shader works in linear light. The sRGB attachment performs the
        // final transfer-function conversion before Core Animation matches it.
        kfx_metal.layer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        kfx_metal.layer.framebufferOnly = YES;
        kfx_metal.layer.opaque = YES;
        kfx_metal.layer.displaySyncEnabled = YES;
        kfx_metal.layer.maximumDrawableCount = KFX_METAL_FRAMES_IN_FLIGHT;

        CGColorSpaceRef colour_space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        if (colour_space == NULL) {
            SDL_SetError("sRGB colour space creation failed");
            LbMacOSMetalDestroy();
            return 0;
        }
        kfx_metal.layer.colorspace = colour_space;
        CGColorSpaceRelease(colour_space);

        int drawable_width = 0;
        int drawable_height = 0;
        SDL_Metal_GetDrawableSize(window, &drawable_width, &drawable_height);
        kfx_metal.layer.drawableSize = CGSizeMake(drawable_width, drawable_height);

        NSError *error = nil;
        id<MTLLibrary> library = [kfx_metal.device newLibraryWithSource:
            [NSString stringWithUTF8String:kfx_metal_shader_source] options:nil error:&error];
        if (library == nil) {
            const char *message = error ? error.localizedDescription.UTF8String : "unknown error";
            SDL_SetError("Metal shader compilation failed: %s", message);
            LbMacOSMetalDestroy();
            return 0;
        }

        id<MTLFunction> vertex_function = [library newFunctionWithName:@"kfx_vertex"];
        id<MTLFunction> fragment_function = [library newFunctionWithName:@"kfx_fragment"];
        MTLRenderPipelineDescriptor *pipeline_descriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipeline_descriptor.label = @"KeeperFX Retina Presenter";
        pipeline_descriptor.vertexFunction = vertex_function;
        pipeline_descriptor.fragmentFunction = fragment_function;
        pipeline_descriptor.colorAttachments[0].pixelFormat = kfx_metal.layer.pixelFormat;
        kfx_metal.pipeline = [kfx_metal.device newRenderPipelineStateWithDescriptor:
            pipeline_descriptor error:&error];
        [pipeline_descriptor release];
        [fragment_function release];
        [vertex_function release];
        [library release];
        if (kfx_metal.pipeline == nil) {
            const char *message = error ? error.localizedDescription.UTF8String : "unknown error";
            SDL_SetError("Metal pipeline creation failed: %s", message);
            LbMacOSMetalDestroy();
            return 0;
        }

        kfx_metal.command_queue = [kfx_metal.device newCommandQueue];
        if (kfx_metal.command_queue == nil) {
            SDL_SetError("Metal command queue creation failed");
            LbMacOSMetalDestroy();
            return 0;
        }
        kfx_metal.command_queue.label = @"KeeperFX Retina Presenter";

        MTLTextureDescriptor *texture_descriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Uint
            width:width height:height mipmapped:NO];
        texture_descriptor.storageMode = MTLStorageModeShared;
        texture_descriptor.usage = MTLTextureUsageShaderRead;
        for (int i = 0; i < KFX_METAL_FRAMES_IN_FLIGHT; i++) {
            kfx_metal.index_textures[i] = [kfx_metal.device newTextureWithDescriptor:texture_descriptor];
            kfx_metal.palette_buffers[i] = [kfx_metal.device
                newBufferWithLength:sizeof(KfxMetalPaletteEntry) * 256
                options:MTLResourceStorageModeShared];
            if ((kfx_metal.index_textures[i] == nil) || (kfx_metal.palette_buffers[i] == nil)) {
                SDL_SetError("Metal framebuffer allocation failed");
                LbMacOSMetalDestroy();
                return 0;
            }
        }
        return 1;
    }
}

int LbMacOSMetalIsActive(void)
{
    return kfx_metal.pipeline != nil;
}

void LbMacOSMetalGetDrawableSize(int *width, int *height)
{
    if (kfx_metal.window == NULL) {
        *width = 0;
        *height = 0;
        return;
    }
    SDL_Metal_GetDrawableSize(kfx_metal.window, width, height);
}

int LbMacOSMetalPresent(const void *pixels, int pitch, const SDL_Color *palette)
{
    @autoreleasepool {
        if (!LbMacOSMetalIsActive()) {
            return 0;
        }

        int drawable_width = 0;
        int drawable_height = 0;
        SDL_Metal_GetDrawableSize(kfx_metal.window, &drawable_width, &drawable_height);
        if ((drawable_width <= 0) || (drawable_height <= 0)) {
            return 1;
        }
        kfx_metal.layer.drawableSize = CGSizeMake(drawable_width, drawable_height);

        id<CAMetalDrawable> drawable = [kfx_metal.layer nextDrawable];
        if (drawable == nil) {
            return 1;
        }

        const unsigned int slot = kfx_metal.frame_index++ % KFX_METAL_FRAMES_IN_FLIGHT;
        id<MTLTexture> index_texture = kfx_metal.index_textures[slot];
        id<MTLBuffer> palette_buffer = kfx_metal.palette_buffers[slot];
        [index_texture replaceRegion:MTLRegionMake2D(0, 0, kfx_metal.width, kfx_metal.height)
            mipmapLevel:0 withBytes:pixels bytesPerRow:pitch];

        KfxMetalPaletteEntry *metal_palette = (KfxMetalPaletteEntry *)palette_buffer.contents;
        kfx_metal_update_palette(metal_palette, palette);

        id<MTLCommandBuffer> command_buffer = [kfx_metal.command_queue commandBuffer];
        if (command_buffer == nil) {
            SDL_SetError("Metal command buffer creation failed");
            return 0;
        }
        MTLRenderPassDescriptor *render_pass = [MTLRenderPassDescriptor renderPassDescriptor];
        render_pass.colorAttachments[0].texture = drawable.texture;
        render_pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        render_pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> encoder = [command_buffer
            renderCommandEncoderWithDescriptor:render_pass];
        if (encoder == nil) {
            SDL_SetError("Metal render encoder creation failed");
            return 0;
        }
        [encoder setRenderPipelineState:kfx_metal.pipeline];
        [encoder setFragmentTexture:index_texture atIndex:0];
        [encoder setFragmentBuffer:palette_buffer offset:0 atIndex:0];
        [encoder setFragmentBytes:&kfx_metal.post_process
            length:sizeof(kfx_metal.post_process) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];
        [command_buffer presentDrawable:drawable];
        [command_buffer commit];
        return 1;
    }
}
