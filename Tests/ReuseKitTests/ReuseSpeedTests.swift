import XCTest
import MLX
@testable import ReuseKit

final class ReuseSpeedTests: XCTestCase {
    func testDecayApproximationBoundsOnGPU() throws {
        try Device.withDefaultDevice(.gpu) {
            let values = (0..<32768).map { Float($0)*80/32767 } + (0..<1024).map { Float($0)*1e-7 }
            let x = MLXArray(values)
            let expected = exp(-x)
            for mode in [ReuseOptimization.poly4,.poly6,.chord3,.chord4] {
                let kernel = MLXFast.metalKernel(name:"decay_bound_\(mode.rawValue)",inputNames:["x"],outputNames:["out"],
                    source:"uint i=thread_position_in_grid.x;if(i<x_shape[0])out[i]=reuse_decay(x[i]);",
                    header:NextKernelSource.decay(mode))
                let actual = kernel([x],grid:(values.count,1,1),threadGroup:(128,1,1),outputShapes:[x.shape],outputDTypes:[.float32])[0]
                let error = abs(actual-expected).max().item(Float.self)
                print("DECAY_BOUND \(mode.rawValue) max_abs=\(error)")
                XCTAssertLessThan(error,5e-6)
                XCTAssertTrue(actual.asArray(Float.self).allSatisfy { $0.isFinite && $0>=0 && $0<=1.000001 })
            }
        }
    }

    func testWarpNormAcrossPartialGroupsAndInputRanges() throws {
        try Device.withDefaultDevice(.gpu) {
            let kernel = MLXFast.metalKernel(name: "test_reuse_warp_norm64",inputNames:["input","scale","offset"],
                outputNames:["out"],source:SpeedKernelSource.warpNorm)
            let weight = MLXArray((0..<64).map { Float(0.6 + Double($0)*0.013) })
            let bias = MLXArray((0..<64).map { Float(sin(Double($0))*0.03) })
            for rows in [1,3,17,966] {
                for (center,amplitude) in [(Float(0),Float(1)),(100,1),(0,1e-5),(0,0)] {
                    let values = (0..<(rows*64)).map { center + amplitude*Float(sin(Double($0)*0.13)) }
                    let input = MLXArray(values).reshaped(1,1,rows,64)
                    let expected = MLXFast.layerNorm(input,weight:weight,bias:bias,eps:1e-5)
                    let actual = kernel([input,weight,bias],grid:(rows*8,1,1),threadGroup:(128,1,1),
                        outputShapes:[input.shape],outputDTypes:[.float32])[0]
                    let error = abs(actual-expected).max().item(Float.self)
                    XCTAssertLessThan(error,2e-4,"rows=\(rows),center=\(center),amplitude=\(amplitude)")
                    XCTAssertTrue(actual.asArray(Float.self).allSatisfy(\.isFinite))
                }
            }
        }
    }
}
