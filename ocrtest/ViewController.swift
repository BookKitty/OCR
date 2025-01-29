import UIKit
import Vision
import CoreImage
import AVFoundation

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
            print("⚠️ 이미지 가져오기 실패")
            return
        }

        print("✅ 이미지 가져오기 성공")
        imageView.image = capturedImage
        detectBookTitleAndAuthor(in: capturedImage)
    }

    // MARK: - CoreML Object Detection
    func detectBookTitleAndAuthor(in image: UIImage) {
        guard let model = try? VNCoreMLModel(for: MyObjectDetector_1().model) else {
            print("⚠️ 모델 로드 실패")
            return
        }

        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

            for observation in results {
                let boundingBox = observation.boundingBox
                print(" 감지된 영역: \(boundingBox)")
                self.cropAndPerformOCR(from: image, boundingBox: boundingBox)
            }
        }

        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try? handler.perform([request])
    }

    // MARK: - 감지된 영역 크롭 후 OCR 실행
    func cropAndPerformOCR(from image: UIImage, boundingBox: CGRect) {
        let croppedImage = cropImage(image, to: boundingBox)
        performOCR(on: croppedImage)
    }

    func cropImage(_ image: UIImage, to boundingBox: CGRect) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = boundingBox.width * CGFloat(cgImage.width)
        let height = boundingBox.height * CGFloat(cgImage.height)
        let x = boundingBox.origin.x * CGFloat(cgImage.width)
        let y = (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height)

        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return image }

        return UIImage(cgImage: croppedCGImage)
    }

    // MARK: - OCR with Vision
    func performOCR(on image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async {
                    self.resultLabel.text = "텍스트를 인식하지 못했습니다."
                }
                return
            }

            let recognizedTexts = observations.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                self.resultLabel.text = recognizedTexts.joined(separator: "\n")
                print("✅ 인식된 텍스트: \(recognizedTexts)")
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko", "en"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
