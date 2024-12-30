//
//  ViewController 2.swift
//  CaptureSensor
//
//  Created by Appari Lalith on 12/11/24.
//  Copyright © 2024 tucan9389. All rights reserved.
//


import UIKit

class FrontViewController: UIViewController {
    
    // UI Components
    @IBOutlet weak var appDescriptionLabel: UITextView!
    @IBOutlet weak var stepsTextView: UITextView!
    @IBOutlet weak var startButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradientBackground()
        setupUI()
        configureStartButton()
    }
    
    // MARK: - Setup Background
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
    
    // MARK: - Setup UI
    private func setupUI() {
        // Style App Description Label
        setupDescriptionLabel()
        
        // Style Steps Text View
        setupStepsTextView()
        
    }

    private func setupDescriptionLabel() {
        appDescriptionLabel.text = """
        This app focuses on wound monitoring using colorimetric assays that visually change in response to wound fluid concentration. We have developed a computer vision algorithm to analyze these changes accurately, overcoming challenges like varying lighting and viewing angles. By leveraging innovative image analysis techniques, the app provides reliable insights into wound conditions, aiding in effective monitoring and assessment.
        """
        appDescriptionLabel.isEditable = false
        appDescriptionLabel.textColor = .darkText
        appDescriptionLabel.textAlignment = .justified
        appDescriptionLabel.font = UIFont(name: "Avenir-Medium", size: 18) ?? .systemFont(ofSize: 18)
        
        appDescriptionLabel.backgroundColor = .clear
        appDescriptionLabel.layer.shadowColor = UIColor.black.cgColor
        appDescriptionLabel.layer.shadowOpacity = 0.1
        appDescriptionLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        appDescriptionLabel.layer.shadowRadius = 3
        appDescriptionLabel.layer.masksToBounds = false
    }
    
    private func setupStepsTextView() {
        stepsTextView.text = """
        Steps to Use the App:
        1. Capture two clear images of the wound assays: one before and one after exposure to the wound.
        2. Press the 'RUN' button to start the evaluation.
        3. View the results, including risk prediction and probability.
        """
        stepsTextView.isEditable = false
        stepsTextView.textColor = .darkText
        stepsTextView.font = UIFont(name: "Avenir-Book", size: 16) ?? .systemFont(ofSize: 16)
        stepsTextView.backgroundColor = UIColor(white: 1.0, alpha: 0.6)
        stepsTextView.layer.cornerRadius = 10
        stepsTextView.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
    }
    
   

    // MARK: - Configure Start Button
    private func configureStartButton() {
        startButton.setTitle("Start Analysis", for: .normal)
        startButton.backgroundColor = UIColor.systemBlue
        startButton.setTitleColor(.white, for: .normal)
        startButton.titleLabel?.font = UIFont(name: "Avenir-Heavy", size: 18) ?? .boldSystemFont(ofSize: 18)
        
        // Enhanced button styling
        startButton.layer.cornerRadius = 12
        startButton.layer.shadowColor = UIColor.systemBlue.cgColor
        startButton.layer.shadowOpacity = 0.4
        startButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        startButton.layer.shadowRadius = 6
        
        // Add a subtle pulse animation
        startButton.addTarget(self, action: #selector(animateButtonPress), for: .touchUpInside)
    }

    // MARK: - Button Animation
    @objc private func animateButtonPress() {
        UIView.animate(withDuration: 0.1, animations: {
            self.startButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.startButton.transform = .identity
            }
        }
        
        startButtonTapped()
    }

    // MARK: - Navigation
    @objc private func startButtonTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let runViewController = storyboard.instantiateViewController(withIdentifier: "ViewController") as? ViewController {
            self.navigationController?.pushViewController(runViewController, animated: true)
        }
    }
}
