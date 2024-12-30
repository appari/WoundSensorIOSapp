import UIKit
import Vision
import CoreMedia
import Foundation
import Photos

extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: self.y * size.height)
    }
}

class Page3ViewController: UIViewController {
    
    // MARK: - UI Properties
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var saveImageButton: UIButton!
    @IBOutlet weak var restartSession: UIButton!
    
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
    
    @IBAction func unwindToHomeVC(segue: UIStoryboardSegue) {}

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
        button.layer.cornerRadius = 10
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 5)
        button.layer.shadowRadius = 10
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
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
    
    @objc func captureButtonPressed(_ sender: UIButton) {
        guard let pixelBuffer = lastCapturedPixelBuffer else {
            print("No captured pixel buffer available")
            return
        }
        
        self.isTapped = true
        self.detectRectangle(in: pixelBuffer)
        self.videoCapture.stop()
    }

    
    @objc func saveImageButtonPressed(_ sender: UIButton) {
        print(predictions)
                
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
                print("Folder name is empty")
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(saveAction)
        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
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
            let imageCount = files.filter { $0.hasPrefix("exposedsensor_") }.count
            
            // Append "skinimage_" to the image name and add an auto-incremented number
            let numberedImageName = "exposedsensor_\(imageCount + 1)_\(imageName).png"
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


    @objc func restartSessionPressed(_ sender: UIButton) {
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
        let location = gesture.location(in: videoPreview)  // Changed from cameraView to videoPreview
        videoCapture.focusOnTap(at: location)
    }
}

// MARK: - VideoCaptureDelegate
extension Page3ViewController: VideoCaptureDelegate {
    // Delegate method for handling video frames
       func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
           // Save the captured pixel buffer for reference
           lastCapturedPixelBuffer = pixelBuffer
           
           // Prevent running inference on multiple frames at the same time
           if !self.isInferencing, let pixelBuffer = pixelBuffer {
               self.isInferencing = true
               // Perform any processing such as detection or prediction
               self.detectRectangle(in: pixelBuffer)
               self.predictUsingVision(pixelBuffer: pixelBuffer)
           }
       }
       
       // Delegate method for handling captured photos
       func videoCapture(_ capture: VideoCapture, didCapturePhoto photo: AVCapturePhoto) {
           // Handle captured photo
           print("Captured photo")
           
           if let photoData = photo.fileDataRepresentation() {
               // Optionally save the photo to the photo library
               UIImageWriteToSavedPhotosAlbum(UIImage(data: photoData)!, nil, nil, nil)
           }
       }
    
}

extension Page3ViewController {
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
    
//    private func imageExtraction(_ observation: VNRectangleObservation, from pixelBuffer: CVPixelBuffer) -> UIImage? {
//        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
//
//        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
//        let boundingBox = observation.boundingBox.applying(transform)
//        let size = ciImage.extent.size
//
//        let normalizedRect = VNImageRectForNormalizedRect(boundingBox, Int(size.width), Int(size.height))
//
//        guard let ciImageCropped = ciImage.cropped(to: normalizedRect) else { return nil }
//
//        let context = CIContext()
//        guard let cgImage = context.createCGImage(ciImageCropped, from: ciImageCropped.extent) else { return nil }
//
//        return UIImage(cgImage: cgImage)
//    }
    
    private func imageExtraction(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) -> UIImage {
        var ciImage = CIImage(cvImageBuffer: buffer)
        
        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)
        
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
