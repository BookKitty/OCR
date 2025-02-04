//
//  BookImageComparator.swift
//  imagesm
//
//  Created by 반성준 on 2/3/25.
//

import UIKit
import Vision

class BookImageComparator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    var completion: ((Float?) -> Void)?
    var targetImage: UIImage?

    /// **카메라 또는 앨범에서 이미지 가져오기**
    func captureOrSelectImage(from viewController: UIViewController, target: UIImage, completion: @escaping (Float?) -> Void) {
        self.completion = completion
        self.targetImage = target
        
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .camera // 카메라 사용 (앨범은 .photoLibrary)
        imagePicker.cameraCaptureMode = .photo
        viewController.present(imagePicker, animated: true, completion: nil)
    }
    
    /// **카메라로 촬영한 이미지 처리**
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let capturedImage = info[.originalImage] as? UIImage else {
            print(" 이미지 가져오기 실패")
            completion?(nil)
            return
        }

        print(" 촬영된 이미지 비교 시작")
        if let targetImage = targetImage {
            compareBookImages(image1: targetImage, image2: capturedImage, completion: completion!)
        }
    }
    
    ///  **두 개의 책 표지 이미지 유사도를 비교하는 함수**
    func compareBookImages(image1: UIImage, image2: UIImage, completion: @escaping (Float?) -> Void) {
        
        let processedImage1 = preprocessImage(image1)
        let processedImage2 = preprocessImage(image2)
        
        guard let featurePrint1 = extractFeaturePrint(from: processedImage1),
              let featurePrint2 = extractFeaturePrint(from: processedImage2) else {
            print(" FeaturePrint 생성 실패")
            completion(nil)
            return
        }

        do {
            var distance: Float = 0.0
            try featurePrint1.computeDistance(&distance, to: featurePrint2)

            // 더 후하게 유사도를 부여하는 변환 공식 (0~100%)
            let similarity = max(0, min(100, (2.2 - distance * 2.0) * 100))

            print(" 유사도 거리: \(distance), 유사도 퍼센트: \(String(format: "%.2f", similarity))%")
            completion(similarity)

        } catch {
            print(" 유사도 계산 실패: \(error)")
            completion(nil)
        }
    }


    
    ///  **FeaturePrint 추출 (iOS 13 이상 지원)**
    private func extractFeaturePrint(from image: UIImage) -> VNFeaturePrintObservation? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()

        do {
            try requestHandler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            print(" FeaturePrint 생성 실패: \(error)")
            return nil
        }
    }

    ///  **이미지 전처리: 대비 보정 + 크기 조정 + Perspective 보정**
    private func preprocessImage(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(1.3, forKey: kCIInputContrastKey) // 대비 증가
        filter?.setValue(0.05, forKey: kCIInputBrightnessKey) // 밝기 조정

        guard let outputImage = filter?.outputImage else { return image }
        
        let context = CIContext()
        if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        
        return image
    }
}
