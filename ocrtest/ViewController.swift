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
        performOCR(on: capturedImage)
    }

    // MARK: - OCR with Vision
    func performOCR(on image: UIImage) {
        guard let adjustedImage = preprocessImage(image) else {
            DispatchQueue.main.async {
                self.resultLabel.text = "이미지 전처리에 실패했습니다."
            }
            return
        }

        imageView.image = adjustedImage // 전처리된 이미지를 표시

        guard let cgImage = adjustedImage.cgImage else {
            DispatchQueue.main.async {
                self.resultLabel.text = "CGImage 생성 실패"
            }
            return
        }

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("⚠️ OCR 실패: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.resultLabel.text = "텍스트 인식 중 오류가 발생했습니다."
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                print("⚠️ 텍스트 인식 실패: 결과 없음")
                DispatchQueue.main.async {
                    self.resultLabel.text = "텍스트를 인식하지 못했습니다."
                }
                return
            }

            // 텍스트 정렬: 위에서 아래 → 왼쪽에서 오른쪽
            let recognizedTexts = observations.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                self.resultLabel.text = recognizedTexts.joined(separator: "\n")
                print("✅ 인식된 텍스트: \(recognizedTexts)")
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko", "en"]
        request.minimumTextHeight = 0.02 // 작은 텍스트 인식

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.resultLabel.text = "OCR 처리 중 오류가 발생했습니다."
                }
                print("⚠️ OCR 처리 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Image Preprocessing
    func preprocessImage(_ image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else {
            print("⚠️ CIImage 생성 실패")
            return nil
        }

        // 그레이스케일 변환 및 대비 증가
        guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
            print("⚠️ Grayscale 변환 필터 생성 실패")
            return nil
        }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey) // 흑백 변환
        grayscaleFilter.setValue(1.2, forKey: kCIInputContrastKey) // 대비 증가

        guard let outputImage = grayscaleFilter.outputImage else {
            print("⚠️ Grayscale 변환 실패")
            return nil
        }

        let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            print("⚠️ CGImage 생성 실패")
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

