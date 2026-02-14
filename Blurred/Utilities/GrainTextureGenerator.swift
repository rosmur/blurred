//
//  GrainTextureGenerator.swift
//  Blurred
//
//  Generates a tileable grain texture using Metal, converts it to
//  a CGImage, and caches the result. The Metal pipeline is only
//  invoked once (or when the seed changes). After that, the image
//  lives in regular memory and is composited by Core Animation
//  with zero ongoing GPU cost from Metal.
//

import Foundation
import Metal
import CoreGraphics

final class GrainTextureGenerator {

    private static var cachedImage: CGImage?
    private static var cachedSeed: UInt32 = 0

    static func grainImage(seed: UInt32 = 42) -> CGImage? {
        if let cached = cachedImage, cachedSeed == seed {
            return cached
        }
        let image = generateViaMetal(width: 512, height: 512, seed: seed)
        cachedImage = image
        cachedSeed = seed
        return image
    }

    // MARK: - Metal generation (one-shot)

    private static func generateViaMetal(width: Int, height: Int, seed: UInt32) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "generateGrainTexture"),
              let pipelineState = try? device.makeComputePipelineState(function: function)
        else {
            // Metal unavailable — fall back to CPU noise
            return generateViaCPU(width: width, height: height, seed: seed)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }

        var seedValue = seed
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&seedValue, length: MemoryLayout<UInt32>.size, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return textureToCGImage(texture)
    }

    // MARK: - Texture → CGImage conversion

    private static func textureToCGImage(_ texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)

        texture.getBytes(
            bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: width, height: height, depth: 1)
            ),
            mipmapLevel: 0
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(
            dataInfo: bytes,
            data: bytes,
            size: byteCount,
            releaseData: { info, _, _ in info?.deallocate() }
        ) else {
            bytes.deallocate()
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - CPU fallback for machines without Metal

    private static func generateViaCPU(width: Int, height: Int, seed: UInt32) -> CGImage? {
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)

        for y in 0..<height {
            for x in 0..<width {
                var h = UInt32(x) &+ UInt32(y) &* UInt32(width) &+ seed
                h ^= h >> 16
                h &*= 0x45d9f3b
                h ^= h >> 16
                h &*= 0x45d9f3b
                h ^= h >> 16
                let value = UInt8((h & 0xFF))
                let offset = y * bytesPerRow + x * 4
                bytes.storeBytes(of: value, toByteOffset: offset, as: UInt8.self)
                bytes.storeBytes(of: value, toByteOffset: offset + 1, as: UInt8.self)
                bytes.storeBytes(of: value, toByteOffset: offset + 2, as: UInt8.self)
                bytes.storeBytes(of: UInt8(255), toByteOffset: offset + 3, as: UInt8.self)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(
            dataInfo: bytes,
            data: bytes,
            size: byteCount,
            releaseData: { info, _, _ in info?.deallocate() }
        ) else {
            bytes.deallocate()
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
