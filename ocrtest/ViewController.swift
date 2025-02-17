import UIKit
import Vision
import CoreImage
import AVFoundation
import NaturalLanguage

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    let imageView = UIImageView()
    let resultLabel = UILabel()
    let captureImageButton = UIButton()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkCameraPermission()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
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
    private func checkCameraPermission() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.resultLabel.text = "카메라 권한이 필요합니다."
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.resultLabel.text = "카메라 접근 권한을 확인해주세요."
            }
        case .authorized: break
        @unknown default: break
        }
    }
    
    // MARK: - Image Capture
    @objc private func captureImage() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            resultLabel.text = "카메라 사용 불가"
            return
        }
        
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        present(picker, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        guard let image = info[.originalImage] as? UIImage else {
            resultLabel.text = "이미지 변환 실패"
            return
        }
        
        imageView.image = image
        processBookScan(image: image)
    }
    
    // MARK: - Core Processing
    private func processBookScan(image: UIImage) {
        guard let model = try? VNCoreMLModel(for: MyObjectDetector5_2().model) else {
            resultLabel.text = "모델 로드 실패"
            return
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("객체 인식 오류: \(error.localizedDescription)")
                return
            }
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                self.resultLabel.text = "인식 결과 없음"
                return
            }
            
            self.processDetections(results, sourceImage: image)
        }
        
        request.usesCPUOnly = false
        request.preferBackgroundProcessing = true
        
        do {
            try VNImageRequestHandler(cgImage: image.cgImage!).perform([request])
        } catch {
            print("Vision 처리 오류: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Detection Processing
    private func processDetections(_ observations: [VNRecognizedObjectObservation], sourceImage: UIImage) {
        let dispatchGroup = DispatchGroup()
        var extractedResults = [String]()
        
        for (index, observation) in observations.enumerated() {
            guard observation.labels.first?.identifier == "titles-or-authors",
                  let croppedImage = getEnhancedCroppedImage(observation, sourceImage: sourceImage) else { continue }
            
            dispatchGroup.enter()
            processOCR(croppedImage) { text in
                if !text.isEmpty {
                    extractedResults.append("📚 \(index+1): \(text)")
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.resultLabel.text = extractedResults.isEmpty ? "인식된 텍스트 없음" : extractedResults.joined(separator: "\n\n")
        }
    }
    
    // MARK: - Image Enhancement
    private func getEnhancedCroppedImage(_ observation: VNRecognizedObjectObservation, sourceImage: UIImage) -> UIImage? {
        let dynamicBox = expandBoundingBox(observation.boundingBox, textLength: 10)
        guard let cropped = cropImage(sourceImage, to: dynamicBox) else { return nil }
        
        return preprocessImage(cropped)
    }
    
    // MARK: - Advanced Preprocessing
    private func preprocessImage(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        // 1. Contrast Limited AHE
        let clahe = ciImage.applyingFilter("CICLAHE", parameters: ["inputClipLimit": 0.03])
        
        // 2. Adaptive Threshold
        let threshold = clahe.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.8])
        
        // 3. Noise Reduction
        let denoised = threshold.applyingFilter("CIMedianFilter")
            .applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": 1.2])
        
        // 4. Sharpening
        let sharpened = denoised.applyingFilter("CISharpenLuminance", parameters: [
            "inputSharpness": 0.95,
            "inputRadius": 1.8
        ])
        
        // 5. Skew Correction
        let corrected = correctSkew(in: sharpened)
        
        guard let cgImage = CIContext().createCGImage(corrected, from: corrected.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Intelligent Bounding Box
    private func expandBoundingBox(_ box: CGRect, textLength: Int) -> CGRect {
        let expansionFactor: CGFloat = {
            switch textLength {
            case 0...5: return 2.2
            case 6...10: return 1.8
            default: return 1.5
            }
        }()
        
        let newWidth = box.width * expansionFactor
        let newHeight = box.height * (expansionFactor * 0.9)
        
        return CGRect(
            x: max(0, box.origin.x - (newWidth - box.width)/2),
            y: max(0, box.origin.y - (newHeight - box.height)/2),
            width: min(1, newWidth),
            height: min(1, newHeight)
        )
    }
    
    // MARK: - OCR Processing
    private func processOCR(_ image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("OCR 오류: \(error.localizedDescription)")
                completion("")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }
            
            let analyzedText = self.analyzeTextStructure(observations)
            let filtered = self.applyPatternFilters(analyzedText)
            let corrected = self.correctKoreanText(filtered)
            
            completion(corrected)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko", "en"]
        request.customWords = ["ISBN", "도서", "출판사"]
        
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            completion("")
        }
    }
    
    // MARK: - Text Analysis
    private func analyzeTextStructure(_ observations: [VNRecognizedTextObservation]) -> String {
        var textBlocks = [(rect: CGRect, text: String)]()
        
        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            textBlocks.append((obs.boundingBox, text))
        }
        
        let lineGroups = Dictionary(grouping: textBlocks) { Int($0.rect.midY * 1000) }
        return lineGroups.values
            .sorted { ($0.first?.rect.minY ?? 0) < ($1.first?.rect.minY ?? 0) }
            .map { $0.sorted { $0.rect.minX < $1.rect.minX }.map { $0.text }.joined(separator: " ") }
            .joined(separator: "\n")
    }
    
    // MARK: - Korean Correction
    private func correctKoreanText(_ text: String) -> String {
        let replacements: [String: String] = [
            "뛌끼": "뜨끼", "햐야": "해야", "따름": "따름",
            "(\\b\\w+\\b) \\1": "$1",  // 반복 단어 제거
            "(?<=[가-힣])\\s+(?=[을를이가])": ""  // 조사 띄어쓰기 교정
        ]
        
        var corrected = text
        replacements.forEach { key, value in
            corrected = corrected.replacingOccurrences(
                of: key,
                with: value,
                options: .regularExpression
            )
        }
        return corrected
    }
    
    // MARK: - Pattern Filtering
    private func applyPatternFilters(_ text: String) -> String {
        let patterns = [
            "(ISBN|isbn).*?\\d{1,5}-\\d{1,7}-\\d{1,7}-\\d",  // ISBN 번호 필터링
            "\\d{4}[년.-]\\s*\\d{1,2}[월.-]\\s*\\d{1,2}일?",  // 날짜 형식 필터링
            "http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+" // URL 필터링
        ]
        
        return text.components(separatedBy: .newlines)
            .filter { line in
                !patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
            }
            .joined(separator: "\n")
    }
    
    // MARK: - Skew Correction
    private func correctSkew(in image: CIImage) -> CIImage {
        guard let detector = CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: nil) else {
            print("⚠️ CIDetector 초기화 실패")
            return image
        }
        
        guard let feature = detector.features(in: image).first as? CIRectangleFeature else {
            print("⚠️ 텍스트 기울기 감지 실패")
            return image
        }
        
        // 각도 계산 (좌상단과 우상단 점을 사용하여 기울기 추정)
        let dx = feature.topRight.x - feature.topLeft.x
        let dy = feature.topRight.y - feature.topLeft.y
        let angle = atan2(dy, dx)
        
        return image.applyingFilter("CIAffineTransform", parameters: [
            kCIInputTransformKey: NSValue(cgAffineTransform: CGAffineTransform(rotationAngle: -angle))
        ])
    }
    
    // MARK: - Image Cropping
    private func cropImage(_ image: UIImage, to box: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width) * box.width
        let height = CGFloat(cgImage.height) * box.height
        let x = CGFloat(cgImage.width) * box.origin.x
        let y = CGFloat(cgImage.height) * (1 - box.origin.y - box.height)
        
        let rect = CGRect(x: x, y: y, width: width, height: height).integral
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
