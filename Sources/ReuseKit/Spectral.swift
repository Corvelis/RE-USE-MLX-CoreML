// SPDX-License-Identifier: Apache-2.0
import Foundation
import MLX
import MLXFFT

enum Spectral {
    static let nFFT = 640, hop = 80
    private static let ola = MLXFast.metalKernel(name: "reuse_fp32_ola_ios",
        inputNames: ["frames", "lengthValue"], outputNames: ["out"],
        source: """
        uint tid=thread_position_in_grid.x;
        uint batches=frames_shape[0],count=frames_shape[1],width=frames_shape[2];
        uint length=lengthValue[0],hop=80;
        if(tid>=batches*length)return;
        uint b=tid/length,t=tid%length;
        uint first=t>=width?(t-width)/hop+1:0;
        uint last=min(t/hop,count-1);
        float value=0.0f;
        for(uint frame=first;frame<=last;frame++){
            value+=frames[b*frames_strides[0]+frame*frames_strides[1]+(t-frame*hop)*frames_strides[2]];
        }
        out[tid]=value;
        """, ensureRowContiguous: false)

    static func window() -> MLXArray {
        let n = MLXArray(0..<nFFT).asType(.float32)
        return 0.5 - 0.5 * cos(2 * Float.pi * n / Float(nFFT))
    }

    static func analysis(_ samples: [Float]) throws -> (MLXArray, MLXArray) {
        guard samples.count > nFFT/2 else { throw ReuseError.invalid("音声が短すぎます。") }
        let pad = nFFT/2
        let padded = Array(samples[1...pad].reversed()) + samples
            + Array(samples[(samples.count-pad-1)..<(samples.count-1)].reversed())
        let count = (padded.count-nFFT)/hop+1
        let frames = asStrided(MLXArray(padded), [count, nFFT], strides: [hop, 1])
        let spectrum = rfft(frames * window().reshaped(1, nFFT), n: nFFT, axis: -1)
        let re = spectrum.realPart(), im = spectrum.imaginaryPart()
        let mag = sqrt(re*re+im*im).log1p().T.expandedDimensions(axis: 0)
        let phase = atan2(im, re).T.expandedDimensions(axis: 0)
        return (mag, phase)
    }

    static func synthesis(_ amp: MLXArray, _ phase: MLXArray, samples: Int) -> [Float] {
        let magnitude = expm1(maximum(amp, MLXArray(Float(0))))
        let zeroCount = (magnitude .== 0).sum(axis: 1, keepDims: true)
        let filtered = which(zeroCount .> (amp.shape[1]/2), MLXArray(Float(0)), amp)
        let expanded = expm1(maximum(filtered, MLXArray(Float(0))))
        let spectrum = (expanded*cos(phase) + (expanded*sin(phase)).asImaginary())
            .transposed(0, 2, 1)
        let count = spectrum.shape[1]
        let win = window().reshaped(1, 1, nFFT)
        let frames = irfft(spectrum, n: nFFT, axis: -1) * win
        let length = nFFT+hop*(count-1)
        let lengthArray = MLXArray([UInt32(length)])
        let signal = ola([frames, lengthArray], grid: (length, 1, 1), threadGroup: (256, 1, 1),
            outputShapes: [[1, length]], outputDTypes: [.float32])[0]
        let envelopeFrames = broadcast(win*win, to: [1, count, nFFT])
        let envelope = ola([envelopeFrames, lengthArray], grid: (length, 1, 1), threadGroup: (256, 1, 1),
            outputShapes: [[1, length]], outputDTypes: [.float32])[0]
        let normalized = signal/maximum(envelope, MLXArray(Float(1e-10)))
        let output = normalized[0, (nFFT/2)..<(length-nFFT/2)]
        eval(output)
        var values = output.asArray(Float.self)
        if values.count < samples { values += Array(repeating: 1e-8, count: samples-values.count) }
        return Array(values.prefix(samples))
    }
}
