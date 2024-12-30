import UIKit
import Vision
import CoreMedia
import Foundation
import Photos

class Page2ViewController: UIViewController {
    
    // MARK: - UI Properties
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var saveImageButton: UIButton!
    @IBOutlet weak var restartSession: UIButton!
    @IBOutlet weak var flashButton: UIButton!
    
    var detectedImage: UIImage?
    weak var delegate: ImagePathDelegate?
    
    // MARK: - Core ML model
    lazy var objectDectectionModel = { return try? YOLOv3Tiny() }()
    
    // MARK: - Vision Properties
    var request: VNCoreMLRequest?
    var visionModel: VNCoreMLModel?
    var isInferencing = false
    
    // MARK: - AV Property
    var videoCapture: VideoCapture!
    let semaphore = DispatchSemaphore(value: 1)
    var lastCapturedPixelBuffer: CVPixelBuffer?
    
    // MARK: - TableView Data
    var predictions: [VNRecognizedObjectObservation] = []
    
    private var maskLayer = CAShapeLayer()
    private var isTapped = false
    private var focusIndicator: CALayer?
    
    var isFlashOn = false // Track flash state


    // MARK: - View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup the model
        setUpModel()
        
        // Setup camera
        setUpCamera()
        
        // Setup capture button action
        captureButton.addTarget(self, action: #selector(captureButtonPressed(_:)), for: .touchUpInside)
        styleButton(captureButton, withColor: .systemRed)
        
        // Setup save image button action
        saveImageButton.addTarget(self, action: #selector(saveImageButtonPressed(_:)), for: .touchUpInside)
        styleButton(saveImageButton, withColor: .systemGreen)
        
        // Restart Session
        restartSession.addTarget(self, action: #selector(restartSessionPressed(_:)), for: .touchUpInside)
        styleButton(restartSession, withColor: .systemBlue)
        
//        flashButton.addTarget(self, action: #selector(toggleFlash(_:)), for: .touchUpInside) // Flash button action
//        styleButton(flashButton, withColor: .systemYellow) // Style flash button


        // Add pinch gesture recognizer
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        videoPreview.addGestureRecognizer(pinchGestureRecognizer)
        
        // Add tap gesture recognizer for focus
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        videoPreview.addGestureRecognizer(tapGesture)
        
        // Set background color
        view.backgroundColor = .systemGray6
    }

    private func styleButton(_ button: UIButton, withColor color: UIColor) {
        button.backgroundColor = color
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.layer.cornerRadius = button.bounds.height / 2
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 5)
        button.layer.shadowRadius = 5
    }


    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - Flash Control
    @objc func toggleFlash(_ sender: UIButton) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            print("Flash not available")
            return
        }
        
        do {
            try device.lockForConfiguration()
            if isFlashOn {
                device.torchMode = .off
                flashButton.setTitle("Flash Off", for: .normal)
            } else {
                try device.setTorchModeOn(level: 1.0)
                flashButton.setTitle("Flash On", for: .normal)
            }
            isFlashOn.toggle()
            device.unlockForConfiguration()
        } catch {
            print("Flash could not be used: \(error)")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.videoCapture.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.videoCapture.stop()
    }
    
    // MARK: - Setup Core ML
    func setUpModel() {
        guard let objectDectectionModel = objectDectectionModel else { fatalError("Failed to load the model") }
        if let visionModel = try? VNCoreMLModel(for: objectDectectionModel.model) {
            self.visionModel = visionModel
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request?.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError("Failed to create vision model")
        }
    }

    // MARK: - SetUp Video
    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 30
        videoCapture.setUp(sessionPreset: .vga640x480) { success in
            if success {
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                self.videoCapture.start()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let previewLayer = videoCapture?.previewLayer {
            previewLayer.frame = videoPreview.bounds
            videoPreview.layer.insertSublayer(previewLayer, at: 0)
        }
    }

    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    fileprivate func animateButton(_ viewToAnimate: UIView) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseIn, animations: {
            viewToAnimate.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }) { (_) in
            UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 2, options: .curveEaseIn, animations: {
                viewToAnimate.transform = CGAffineTransform(scaleX: 1, y: 1)
            }, completion: nil)
        }
    }

    @objc func captureButtonPressed(_ sender: UIButton) {
        animateButton(sender)
        guard let pixelBuffer = lastCapturedPixelBuffer else {
            print("No captured pixel buffer available")
            return
        }
        
//        if predictions.isEmpty {
////            showNoRectangleAlert()
//            return
//        }
        
        self.isTapped = true
        self.detectRectangle(in: pixelBuffer)
        self.videoCapture.stop()
    }
    
    @objc func saveImageButtonPressed(_ sender: UIButton) {
//        
//        if predictions.isEmpty {
////            showNoRectangleAlert()
//            return
//        }
        
        animateButton(sender)
        guard let detectedImage = self.detectedImage else {
            print("No detected image available")
            return
        }

        let alert = UIAlertController(title: "Save Image", message: "Enter folder and image name:", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Concentration / Folder name"
        }
        alert.addTextField { textField in
            textField.placeholder = "Image name"
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let folderName = alert.textFields?[0].text, !folderName.isEmpty,
               let imageName = alert.textFields?[1].text {
                self?.saveImageToDocuments(image: detectedImage, folderName: folderName, imageName: imageName)
            } else {
                print("Folder name or image name is empty")
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(saveAction)
        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
    }

    
    private func showNoRectangleAlert() {
        let alert = UIAlertController(title: "No Rectangle Detected", message: "No rectangle was found in the frame. Please try again.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func saveImageToDocuments(image: UIImage, folderName: String = "DefaultFolder", imageName: String = "DefaultImage") {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Append "Study_" to the folder name
        let folderURL = documentsDirectory.appendingPathComponent("study_\(folderName)")

        do {
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Get list of existing files in the folder
            let files = try fileManager.contentsOfDirectory(atPath: folderURL.path)
            
            // Filter out files with the "skinimage_" prefix to count them
            let imageCount = files.filter { $0.hasPrefix("basesensor_") }.count
            
            // Append "skinimage_" to the image name and add an auto-incremented number
            let numberedImageName = "basesensor_\(imageCount + 1)_\(imageName).png"
            let imageURL = folderURL.appendingPathComponent(numberedImageName)
            
            if let data = image.pngData() {
                try data.write(to: imageURL)
                print("Image saved at path: \(imageURL.path)")
                
                DispatchQueue.main.async {
                    self.getImagePath(for: imageURL) { path in
                        if let path = path {
                            self.notifyImagePathCaptured(path)
                            self.showSuccessAlert(message: "Image saved successfully at path: \(path)")
                        } else {
                            self.showFailureAlert(message: "Failed to retrieve image path.")
                        }
                    }
                }
            } else {
                print("Failed to convert image to PNG data")
                self.showFailureAlert(message: "Failed to convert image to PNG data")
            }
        } catch {
            print("Error saving image to folder: \(error.localizedDescription)")
            self.showFailureAlert(message: "Error saving image: \(error.localizedDescription)")
        }
    }

    private func getImagePath(for imageURL: URL, completion: @escaping (String?) -> Void) {
        // Directly use the URL path as it is already the image path
        completion(imageURL.path)
    }

    private func notifyImagePathCaptured(_ path: String) {
        // Notify the delegate with the image path
        delegate?.didReceiveImagePath(path, from: self)
    }

    func showSuccessAlert(message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    func showFailureAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    private func addFocusIndicator(at point: CGPoint) {
        focusIndicator?.removeFromSuperlayer() // Remove existing focus indicator
        let indicator = CALayer()
        indicator.frame = CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)
        indicator.borderColor = UIColor.yellow.cgColor
        indicator.borderWidth = 2
        indicator.cornerRadius = 30
        indicator.opacity = 0.8
        videoPreview.layer.addSublayer(indicator)
        focusIndicator = indicator
        
        // Animate disappearance
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            indicator.removeFromSuperlayer()
        }
    }

    
    @objc func restartSessionPressed(_ sender: UIButton) {
        animateButton(sender)

        // Reset all variables related to detected image and rectangle
        lastCapturedPixelBuffer = nil
        detectedImage = nil
        predictions.removeAll()   // Clear predictions
        isTapped = false          // Reset tap state
        removeMask()              // Remove any drawn bounding boxes

        // Restart the session
        self.viewWillAppear(true)
    }

    
    @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard let videoCapture = videoCapture else { return }
        if sender.state == .changed {
            videoCapture.updateZoomFactor(scale: sender.scale)
            sender.scale = 1.0
        }
    }
    
    // Handle tap gesture for focus
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: videoPreview)
        
        // Add focus indicator at the tap location
        addFocusIndicator(at: location)
        
        videoCapture.focusOnTap(at: location)
    
    }

}

// MARK: - VideoCaptureDelegate
extension Page2ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        lastCapturedPixelBuffer = pixelBuffer
        if !self.isInferencing, let pixelBuffer = pixelBuffer {
            self.isInferencing = true
            self.detectRectangle(in: pixelBuffer)
            self.predictUsingVision(pixelBuffer: pixelBuffer)
        }
    }
}

extension Page2ViewController {
    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        guard let request = request else { fatalError() }
        self.semaphore.wait()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }

    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let predictions = request.results as? [VNRecognizedObjectObservation] {
            self.predictions = predictions
            DispatchQueue.main.async {
                self.isInferencing = false
            }
        } else {
            self.isInferencing = false
        }
        self.semaphore.signal()
    }
    
    private func detectRectangle(in image: CVPixelBuffer) {
        let request = VNDetectRectanglesRequest { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                guard let results = request.results as? [VNRectangleObservation] else { return }
                self.removeMask()
                guard let rect = results.first else { return }
                self.drawBoundingBox(rect: rect)
                
                if self.isTapped {
                    self.isTapped = false
                    self.detectedImage = self.imageExtraction(rect, from: image)
                }
            }
        }
        
        request.minimumAspectRatio = VNAspectRatio(0.7)
        request.maximumAspectRatio = VNAspectRatio(1.2)
        request.minimumSize = Float(0.2)
        request.maximumObservations = 1
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try? imageRequestHandler.perform([request])
    }
    
    private func imageExtraction(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) -> UIImage {
        var ciImage = CIImage(cvImageBuffer: buffer)
        
        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)
        
        print(observation.topLeft, observation.topRight, ciImage.extent.size)
        // pass filters to extract/rectify the image
        ciImage = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])
        
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let output = UIImage(cgImage: cgImage!)
        
        //return image
        return output
    }
    
    func drawBoundingBox(rect: VNRectangleObservation) {
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -videoPreview.bounds.height)
        let scale = CGAffineTransform.identity.scaledBy(x: videoPreview.bounds.width, y: videoPreview.bounds.height)
        let bounds = rect.boundingBox.applying(scale).applying(transform)
        createLayer(in: bounds)
    }
    
    func createLayer(in rect: CGRect) {
        maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.cornerRadius = 10
        maskLayer.opacity = 1
        maskLayer.borderColor = UIColor.systemYellow.cgColor
        maskLayer.borderWidth = 4.0
        maskLayer.shadowColor = UIColor.black.cgColor
        maskLayer.shadowOpacity = 0.5
        maskLayer.shadowOffset = CGSize(width: 0, height: 2)
        maskLayer.shadowRadius = 5
        videoPreview.layer.addSublayer(maskLayer)
    }

    
    private func removeMask() {
        maskLayer.removeFromSuperlayer()
    }
}
