import UIKit
import CoreImage

protocol ImagePathDelegate: AnyObject {
    func didReceiveImagePath(_ path: String, from controller: UIViewController)
}

class ViewController: UIViewController {
    // UI Components
    @IBOutlet weak var runScriptButton: UIButton!
    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var capturedImageView: UIImageView!
    @IBOutlet weak var standardImageView: UIImageView!
    
    // Activity Indicator
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let activityIndicatorBackgroundView = UIView()

    // Image paths from Page2 and Page3
    var capturedImagePath: String = ""
    var standardImagePath: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize UI Components
        setupUI()
        setupActivityIndicator()
    }

    // MARK: - UI Setup
    private func setupUI() {
        runScriptButton.addTarget(self, action: #selector(runScriptButtonPressed(_:)), for: .touchUpInside)
        setupGradientBackground()
        styleRunScriptButton()
        styleResultLabel()
        styleImageViews()
    }
    
    private func setupGradientBackground() {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = view.bounds
        gradientLayer.colors = [
            UIColor(red: 0.85, green: 0.94, blue: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)
    }
    private func setupActivityIndicator() {
        // Customize background view
        activityIndicatorBackgroundView.frame = view.bounds
        activityIndicatorBackgroundView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        activityIndicatorBackgroundView.isHidden = true
        view.addSubview(activityIndicatorBackgroundView)
        
        // Customize activity indicator
        activityIndicator.color = .white
        activityIndicator.center = view.center
        activityIndicatorBackgroundView.addSubview(activityIndicator)
    }

    private func styleRunScriptButton() {
        runScriptButton.backgroundColor = UIColor.systemBlue
        runScriptButton.setTitleColor(.white, for: .normal)
        runScriptButton.layer.cornerRadius = 10
        runScriptButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        runScriptButton.layer.shadowColor = UIColor.black.cgColor
        runScriptButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        runScriptButton.layer.shadowOpacity = 0.3
        runScriptButton.layer.shadowRadius = 4
    }

    private func styleResultLabel() {
        resultLabel.text = "Result will appear here"
        resultLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        resultLabel.textColor = UIColor.darkGray
        resultLabel.numberOfLines = 0
        resultLabel.textAlignment = .center
        resultLabel.layer.cornerRadius = 8
        resultLabel.layer.borderWidth = 1
        resultLabel.layer.borderColor = UIColor.lightGray.cgColor
        resultLabel.layer.masksToBounds = true
//        resultLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
    }

    private func styleImageViews() {
        [resultLabel, capturedImageView, standardImageView].forEach { imageView in
            imageView?.contentMode = .scaleAspectFit
            imageView?.layer.borderWidth = 0 // Remove borders
            imageView?.backgroundColor = .white // Set background to white
            imageView?.layer.cornerRadius = 0 // Remove rounded corners (optional)
            imageView?.layer.masksToBounds = true
        }
    }

    
    @IBAction func btnTapped(_ sender: UIView) {
        animateButton(sender)
        let storyboard = self.storyboard?.instantiateViewController(withIdentifier: "Page2ViewController") as! Page2ViewController
        storyboard.delegate = self  // Set delegate to receive the image path
        self.navigationController?.pushViewController(storyboard, animated: true)
    }
    
    @IBAction func btnTapped3(_ sender: UIView) {
        animateButton(sender)
        let storyboard = self.storyboard?.instantiateViewController(withIdentifier: "Page3ViewController") as! Page3ViewController
        storyboard.delegate = self  // Set delegate to receive the image path
        self.navigationController?.pushViewController(storyboard, animated: true)
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

    func calculateAverageBrightness(for image: UIImage) -> Float? {
        guard let ciImage = CIImage(image: image) else {
            print("Error: Failed to create CIImage.")
            return nil
        }
        
        let luminanceFilter = CIFilter(name: "CIAreaAverage")!
        luminanceFilter.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let outputImage = luminanceFilter.outputImage else {
            print("Error: Failed to apply luminance filter.")
            return nil
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext()
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let red = Float(bitmap[0]) / 255.0
        let green = Float(bitmap[1]) / 255.0
        let blue = Float(bitmap[2]) / 255.0
        
        // Calculate luminance using Rec. 709 formula
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    func isBrightnessSimilar(image1: UIImage, image2: UIImage, percentageThreshold: Float = 10.0) -> Bool {
        guard let brightness1 = calculateAverageBrightness(for: image1),
              let brightness2 = calculateAverageBrightness(for: image2) else {
            print("Error: Unable to calculate brightness.")
            return false
        }
        
        let percentageChange = abs(brightness1 - brightness2) / brightness2 * 100
        print("Brightness of Standard Image: \(brightness2)")
        print("Brightness of Captured Image: \(brightness1)")
        print("Percentage Change: \(percentageChange)%")
        
        return percentageChange <= percentageThreshold
    }

    
    @objc func runScriptButtonPressed(_ sender: UIButton) {
        animateButton(sender)
       
           
       
        let alert = UIAlertController(title: "Enter IP", message: "Please enter the IP address of the backend server", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "IP address"
        }
        
        let saveAction = UIAlertAction(title: "Run", style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let ipAddress = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !ipAddress.isEmpty else {
                print("IP address is empty")
                self.resultLabel.text = "Error: IP address is empty"
                return
            }
            
            guard let capturedImage = UIImage(contentsOfFile: self.capturedImagePath),
                  let standardImage = UIImage(contentsOfFile: self.standardImagePath) else {
                self.resultLabel.text = "Error: Unable to load images for brightness check."
                return
            }
            
            if self.isBrightnessSimilar(image1: capturedImage, image2: standardImage, percentageThreshold: 50.0) {
                self.resultLabel.text = "Image quality/Lighting conditions are similar (within acceptable range)."
            } else {
                self.resultLabel.text = "Image quality/Lighting conditions differ significantly (exceeds threshold)."
                return
            }
            
//            if self.isValidIPAddress(ipAddress) {
//                print("IP Address: \(ipAddress)")
            self.showActivityIndicator()
            self.sendPostRequest(ipaddress: ipAddress)
//            } else {
//                print("Error: Invalid IP Address")
//                self.resultLabel.text = "Error: Invalid IP Address"
//            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
    }
    
    private func showActivityIndicator() {
        activityIndicatorBackgroundView.isHidden = false
        activityIndicator.startAnimating()
    }

    private func hideActivityIndicator() {
        activityIndicator.stopAnimating()
        activityIndicatorBackgroundView.isHidden = true
    }
    
    // Function to check if an IP address is valid
    func isValidIPAddress(_ ip: String) -> Bool {
        var sin = sockaddr_in()
        return ip.withCString { cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) } == 1
    }

    func sendPostRequest(ipaddress: String) {
        // Check if image paths are valid and images can be loaded
        guard !capturedImagePath.isEmpty, !standardImagePath.isEmpty else {
            print("Error: Image paths are empty")
            resultLabel.text = "Error: Image paths are empty"
            hideActivityIndicator()
            return
        }
        
        guard let capturedImage = UIImage(contentsOfFile: capturedImagePath),
              let standardImage = UIImage(contentsOfFile: standardImagePath) else {
            print("Error: Unable to load images from paths")
            resultLabel.text = "Error: Unable to load images from paths"
            hideActivityIndicator()
            return
        }
        
        // Convert images to base64
        guard let capturedImageData = capturedImage.jpegData(compressionQuality: 1.0)?.base64EncodedString(),
              let standardImageData = standardImage.jpegData(compressionQuality: 1.0)?.base64EncodedString() else {
            print("Error: Failed to convert images to base64")
            resultLabel.text = "Error: Failed to convert images to base64"
            hideActivityIndicator()
            return
        }

        // Construct the API URL
        guard let url = URL(string: "https://7yuc4ou0sh.execute-api.us-west-2.amazonaws.com/dev-stage") else {
            print("Error: Invalid URL")
            resultLabel.text = "Error: Invalid URL"
            hideActivityIndicator()
            return
        }
        
        // Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare the payload
        let body: [String: Any] = [
                "baseimage": capturedImageData,
                "exposedimage": standardImageData
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Error: Failed to serialize JSON: \(error.localizedDescription)")
            resultLabel.text = "Error: Failed to serialize JSON"
            hideActivityIndicator()
            return
        }
        
        // Send the request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.hideActivityIndicator()
                
                if let error = error {
                    print("Request error: \(error.localizedDescription)")
                    self.resultLabel.text = "Error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Error: Invalid response")
                    self.resultLabel.text = "Error: Invalid response"
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("Error: HTTP \(httpResponse.statusCode)")
                    self.resultLabel.text = "Error: HTTP \(httpResponse.statusCode). Failed to run the script."
                    return
                }
                
                guard let data = data, let responseString = String(data: data, encoding: .utf8) else {
                    print("Error: No data received or data is not UTF-8 encoded")
                    self.resultLabel.text = "Error: No data"
                    return
                }
                
                do {
                    // Parse JSON response
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let message = jsonResponse["message"] as? String,
                       let outputValue = jsonResponse["output_value"] {
                        print("Message: \(message), Output: \(outputValue)")
                        self.resultLabel.text = "Message: \(message)\nOutput: \(outputValue)"
                    } else {
                        print("Error: 'message' or 'output_value' key not found")
                        self.resultLabel.text = "Error: Invalid response format"
                    }
                } catch {
                    print("Error: Failed to parse JSON: \(error.localizedDescription)")
                    self.resultLabel.text = "Error: Failed to parse JSON"
                }
            }
        }
        
        task.resume()
    }

    
    

    


}

// Assuming Page2ViewController and Page3ViewController have delegate properties to pass back data
extension ViewController: ImagePathDelegate {
    func didReceiveImagePath(_ path: String, from controller: UIViewController) {
        if controller is Page3ViewController {
            capturedImagePath = path
            if let capturedImage = UIImage(contentsOfFile: path) {
                capturedImageView.image = capturedImage
            }
        } else if controller is Page2ViewController {
            standardImagePath = path
            if let standardImage = UIImage(contentsOfFile: path) {
                standardImageView.image = standardImage
            }
        }
    }
}
