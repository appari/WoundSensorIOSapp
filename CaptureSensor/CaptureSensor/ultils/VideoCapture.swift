import UIKit
import AVFoundation
import CoreVideo

public protocol VideoCaptureDelegate: AnyObject {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
}

public class VideoCapture: NSObject {
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: VideoCaptureDelegate?
    var captureDevice: AVCaptureDevice?
    public var fps = 140 // Increased FPS
    
    var currentZoomFactor: CGFloat = 1.0
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let queue = DispatchQueue(label: "com.highquality.camera-queue", qos: .userInteractive)
    
    var lastTimestamp = CMTime()
    
    public var isTorchEnabled: Bool = false
    public var isFlipCameraEnabled: Bool = true
    
    public func setUp(sessionPreset: AVCaptureSession.Preset = .hd4K3840x2160,
                      completion: @escaping (Bool) -> Void) {
        self.setUpCamera(sessionPreset: sessionPreset, completion: { success in
            completion(success)
        })
    }
    
    func setUpCamera(sessionPreset: AVCaptureSession.Preset, completion: @escaping (_ success: Bool) -> Void) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Error: no video devices available")
            completion(false)
            return
        }
        self.captureDevice = captureDevice
        
        do {
            try captureDevice.lockForConfiguration()
            
            // Set highest frame rate available
            let formats = captureDevice.formats
            let maxFrameRate = formats.max { $0.videoSupportedFrameRateRanges[0].maxFrameRate < $1.videoSupportedFrameRateRanges[0].maxFrameRate }
            if let maxFormat = maxFrameRate {
                captureDevice.activeFormat = maxFormat
                captureDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps))
                captureDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            }
            
            // Keep focus and zoom enabled while removing other auto settings like exposure or white balance.
            if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                captureDevice.focusMode = .continuousAutoFocus
            }
            
            
            // Enable zooming by adjusting the zoom factor
            captureDevice.videoZoomFactor = currentZoomFactor
            
            // Disable automatic exposure and white balance adjustments to prevent color changes
            if captureDevice.isWhiteBalanceModeSupported(.locked) {
                captureDevice.whiteBalanceMode = .locked
            }
            if captureDevice.isExposureModeSupported(.locked) {
                captureDevice.exposureMode = .locked
            }
            
            
            // Lock white balance gains (color temperature adjustments)
            if captureDevice.isWhiteBalanceModeSupported(.locked) {
                let currentGains = captureDevice.deviceWhiteBalanceGains
                captureDevice.setWhiteBalanceModeLocked(with: currentGains, completionHandler: nil)
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("Error: Could not configure camera settings")
            completion(false)
            return
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Error: could not create AVCaptureDeviceInput")
            completion(false)
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer
        
        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
        ]
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
        
        captureSession.commitConfiguration()
        
        completion(true)
    }
    
    public func start() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    // Update zoom factor on tap or pinch gesture
    public func updateZoomFactor(scale: CGFloat) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            
            // Smooth zoom animation
            let newZoomFactor = min(max(currentZoomFactor * scale, 1.0), device.activeFormat.videoMaxZoomFactor)
            device.videoZoomFactor = newZoomFactor
            currentZoomFactor = newZoomFactor
            
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to update zoom factor: \(error)")
        }
    }

    // Update focus and zoom on tap
    func updateFocusAndExposure(at point: CGPoint) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = currentZoomFactor

            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to update focus and exposure: \(error)")
        }
    }
    
    public func focusOnTap(at point: CGPoint) {
        guard let previewLayer = previewLayer else { return }
        let convertedPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        updateFocusAndExposure(at: convertedPoint)
    }
    
    public func addOverlay(_ overlay: CALayer) {
        guard let previewLayer = previewLayer else { return }
        overlay.frame = previewLayer.bounds
        previewLayer.insertSublayer(overlay, at: 1)
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let deltaTime = timestamp - lastTimestamp
        if deltaTime >= CMTimeMake(value: 1, timescale: Int32(fps)) {
            lastTimestamp = timestamp
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Optionally handle dropped frames
    }
}
