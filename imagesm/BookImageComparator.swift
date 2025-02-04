//
//  BookImageComparator.swift
//  imagesm
//
//  Created by 반성준 on 2/3/25.
//

import UIKit
import Vision

class BookImageComparator: NSObject {
    
    var completion: ((Float?) -> Void)?
    
    /// **URL을 통한 책 표지 비교**
    func compareBookImages(url1: URL, url2: URL, completion: @escaping (Float?) -> Void) {
        self.completion = completion
        
        downloadImage(from: url1) { image1 in
            guard let image1 = image1 else {
                print("첫 번째 이미지 로드 실패")
                completion(nil)
                return
            }
            
            self.downloadImage(from: url2) { image2 in
                guard let image2 = image2 else {
                    print("두 번째 이미지 로드 실패")
                    completion(nil)
                    return
                }
                
                self.compareBookImages(image1: image1, image2: image2, completion: completion)
            }
        }
    }
    
    /// **UIImage를 통한 책 표지 비교 (로컬 이미지)**
    func compareBookImages(image1: UIImage, image2: UIImage, completion: @escaping (Float?) -> Void) {
        let processedImage1 = preprocessImage(image1)
        let processedImage2 = preprocessImage(image2)
        
        guard let featurePrint1 = extractFeaturePrint(from: processedImage1),
              let featurePrint2 = extractFeaturePrint(from: processedImage2) else {
            print("FeaturePrint 생성 실패")
            completion(nil)
            return
        }

        do {
            var distance: Float = 0.0
            try featurePrint1.computeDistance(&distance, to: featurePrint2)

            // 유사도 변환 공식 (0.75 → 33%, 최대값 100%)
            let similarity = max(0, min(100, (2.5 - distance * 2.5) * 100))

            print("유사도 거리: \(distance), 유사도 퍼센트: \(String(format: "%.2f", similarity))%")
            completion(similarity)

        } catch {
            print("유사도 계산 실패: \(error)")
            completion(nil)
        }
    }
    
    /// **URL을 통한 이미지 다운로드**
    private func downloadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, let image = UIImage(data: data), error == nil else {
                print("이미지 다운로드 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                completion(nil)
                return
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
        task.resume()
    }

    /// **FeaturePrint 추출**
    private func extractFeaturePrint(from image: UIImage) -> VNFeaturePrintObservation? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()

        do {
            try requestHandler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            print("FeaturePrint 생성 실패: \(error)")
            return nil
        }
    }

    /// **이미지 전처리: 대비 보정 + 크기 조정**
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
