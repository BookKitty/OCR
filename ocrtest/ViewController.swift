//
//  ViewController.swift
//  ocrtest
//
//  Created by 반성준 on 1/22/25.
//

import UIKit
import Vision
import CoreImage
import AVFoundation

struct OCRTextBlock {
    let text: String
    let boundingBox: CGRect
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let imageView = UIImageView()
    let resultLabel = UILabel()
    let captureImageButton = UIButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkCameraPermission()
    }

    // MARK: - UI Setup
    func setupUI() {
        view.backgroundColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        captureImageButton.setTitle("텍스트 인식", for: .normal)
        captureImageButton.setTitleColor(.systemBlue, for: .normal)
        captureImageButton.addTarget(self, action: #selector(captureImage), for: .touchUpInside)
        captureImageButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureImageButton)

        resultLabel.numberOfLines = 0
        resultLabel.textColor = .black
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),

            captureImageButton.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            captureImageButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            resultLabel.topAnchor.constraint(equalTo: captureImageButton.bottomAnchor, constant: 20),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Camera Permission
    func checkCameraPermission() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.resultLabel.text = "카메라 권한이 필요합니다. 설정에서 권한을 허용해주세요."
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.resultLabel.text = "카메라 권한이 거부되었습니다. 설정에서 권한을 허용해주세요."
            }
        case .authorized:
            print("✅ 카메라 권한이 허용되었습니다.")
        @unknown default:
            break
        }
    }

    // MARK: - Capture Image
    @objc func captureImage() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            resultLabel.text = "카메라를 사용할 수 없습니다."
            return
        }

        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .camera
        imagePicker.cameraCaptureMode = .photo
        imagePicker.modalPresentationStyle = .fullScreen
        present(imagePicker, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)

        guard let capturedImage = info[.originalImage] as? UIImage else {
            DispatchQueue.main.async {
                self.resultLabel.text = "이미지를 가져오지 못했습니다."
            }
            return
        }

        print("✅ 이미지 가져오기 성공")
        imageView.image = capturedImage
        detectBookElements(in: capturedImage)
    }

    // MARK: - CoreML Object Detection
    func detectBookElements(in image: UIImage) {
        guard let model = try? VNCoreMLModel(for: MyObjectDetector5_2().model) else {
            print("⚠️ 모델 로드 실패")
            return
        }

        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            var extractedTexts: [OCRTextBlock] = []

            let dispatchGroup = DispatchGroup()

            for observation in results {
                if observation.labels.first?.identifier == "titles-or-authors" {
                    let expandedBox = self.expandBoundingBox(observation.boundingBox, factor: 1.5)
                    let croppedImage = self.cropImage(image, to: expandedBox)

                    dispatchGroup.enter()
                    self.performOCR(on: croppedImage) { recognizedText in
                        if !recognizedText.isEmpty {
                            extractedTexts.append(OCRTextBlock(text: recognizedText, boundingBox: expandedBox))
                        }
                        dispatchGroup.leave()
                    }
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.displayExtractedTexts(extractedTexts)
            }
        }

        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try? handler.perform([request])
    }

    // MARK: - OCR 수행
    func performOCR(on image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else { return }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                completion("")
                return
            }

            let recognizedTexts = observations.compactMap { $0.topCandidates(1).first?.string }
            completion(recognizedTexts.joined(separator: " "))
        }

        request.recognitionLanguages = ["ko", "en"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.002

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    // MARK: - 이미지 크롭 (OCR 인식 정확도 개선)
    func cropImage(_ image: UIImage, to boundingBox: CGRect) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let rect = CGRect(
            x: boundingBox.origin.x * CGFloat(cgImage.width),
            y: (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height),
            width: boundingBox.width * CGFloat(cgImage.width),
            height: boundingBox.height * CGFloat(cgImage.height)
        )

        guard let croppedCGImage = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: croppedCGImage)
    }

    // MARK: - OCR 결과 표시
    func displayExtractedTexts(_ texts: [OCRTextBlock]) {
        let extractedText = texts.map { $0.text }.joined(separator: "\n")
        DispatchQueue.main.async {
            self.resultLabel.text = extractedText
        }
    }

    // MARK: - OCR 영역 확장 (걸쳐있는 글자까지 포함)
    func expandBoundingBox(_ boundingBox: CGRect, factor: CGFloat) -> CGRect {
        let x = boundingBox.origin.x - (boundingBox.width * (factor - 1) / 2)
        let y = boundingBox.origin.y - (boundingBox.height * (factor - 1) / 2)
        let width = boundingBox.width * factor
        let height = boundingBox.height * factor

        return CGRect(x: max(0, x), y: max(0, y), width: min(1, width), height: min(1, height))
    }
}
