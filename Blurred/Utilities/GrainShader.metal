//
//  GrainShader.metal
//  Blurred
//
//  Metal compute kernel for one-time grain texture generation.
//  This runs ONCE to produce a 512x512 noise texture, then the
//  result is handed off to Core Animation as a static tiled layer.
//  Ongoing Metal GPU cost: zero.
//

#include <metal_stdlib>
using namespace metal;

kernel void generateGrainTexture(
    texture2d<float, access::write> output [[texture(0)]],
    constant uint &seed [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();

    if (gid.x >= width || gid.y >= height) return;

    // xxhash-inspired integer hash for high-quality uniform noise
    uint h = gid.x + gid.y * width + seed;
    h ^= h >> 16;
    h *= 0x45d9f3bu;
    h ^= h >> 16;
    h *= 0x45d9f3bu;
    h ^= h >> 16;

    float noise = float(h & 0xFFFFu) / 65535.0;

    output.write(float4(noise, noise, noise, 1.0), gid);
}
