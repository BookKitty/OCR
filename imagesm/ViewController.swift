//
//  ViewController.swift
//  imagesm
//
//  Created by 반성준 on 2/3/25.
//

import UIKit

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    let imageView1 = UIImageView()
    let imageView2 = UIImageView()
    let urlTextField1 = UITextField()
    let urlTextField2 = UITextField()
    let compareButton = UIButton()
    let resultLabel = UILabel()
    var selectedImageView: UIImageView?
    
    let imageComparator = BookImageComparator()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI 설정
    func setupUI() {
        view.backgroundColor = .white
        
        imageView1.contentMode = .scaleAspectFit
        imageView2.contentMode = .scaleAspectFit
        imageView1.layer.borderColor = UIColor.gray.cgColor
        imageView2.layer.borderColor = UIColor.gray.cgColor
        imageView1.layer.borderWidth = 1
        imageView2.layer.borderWidth = 1
        
        urlTextField1.placeholder = "첫 번째 이미지 URL 입력"
        urlTextField1.borderStyle = .roundedRect
        urlTextField1.addTarget(self, action: #selector(loadImagePreview1), for: .editingDidEnd)

        urlTextField2.placeholder = "두 번째 이미지 URL 입력"
        urlTextField2.borderStyle = .roundedRect
        urlTextField2.addTarget(self, action: #selector(loadImagePreview2), for: .editingDidEnd)
        
        compareButton.setTitle("비교하기", for: .normal)
        compareButton.setTitleColor(.white, for: .normal)
        compareButton.backgroundColor = .systemBlue
        compareButton.addTarget(self, action: #selector(compareImages), for: .touchUpInside)
        
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 2
        resultLabel.text = "책 표지를 비교하려면 이미지를 선택하세요."

        let stackView = UIStackView(arrangedSubviews: [imageView1, urlTextField1, imageView2, urlTextField2, compareButton, resultLabel])
        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            imageView1.heightAnchor.constraint(equalToConstant: 200),
            imageView2.heightAnchor.constraint(equalToConstant: 200),
            compareButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        let tapGesture1 = UITapGestureRecognizer(target: self, action: #selector(selectImage1))
        let tapGesture2 = UITapGestureRecognizer(target: self, action: #selector(selectImage2))
        imageView1.addGestureRecognizer(tapGesture1)
        imageView2.addGestureRecognizer(tapGesture2)
        imageView1.isUserInteractionEnabled = true
        imageView2.isUserInteractionEnabled = true
    }
    
    // MARK: - 이미지 선택 (카메라 또는 앨범)
    @objc func selectImage1() { selectImage(for: imageView1) }
    @objc func selectImage2() { selectImage(for: imageView2) }

    func selectImage(for imageView: UIImageView) {
        selectedImageView = imageView
        let alert = UIAlertController(title: "이미지 선택", message: nil, preferredStyle: .actionSheet)
        
        let cameraAction = UIAlertAction(title: "카메라", style: .default) { _ in self.openCamera() }
        let galleryAction = UIAlertAction(title: "앨범", style: .default) { _ in self.openGallery() }
        let cancelAction = UIAlertAction(title: "취소", style: .cancel, handler: nil)
        
        alert.addAction(cameraAction)
        alert.addAction(galleryAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }

    func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            resultLabel.text = "카메라를 사용할 수 없습니다."
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        present(picker, animated: true)
    }

    func openGallery() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        guard let selectedImage = info[.originalImage] as? UIImage,
              let selectedImageView = selectedImageView else { return }

        selectedImageView.image = selectedImage
    }

    // MARK: - URL을 통한 이미지 미리보기 로드
    @objc func loadImagePreview1() { loadImagePreview(from: urlTextField1.text, into: imageView1) }
    @objc func loadImagePreview2() { loadImagePreview(from: urlTextField2.text, into: imageView2) }

    func loadImagePreview(from urlString: String?, into imageView: UIImageView) {
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        
        DispatchQueue.global().async {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    imageView.image = image
                }
            }
        }
    }

    // MARK: - 이미지 비교 실행 (URL 또는 로컬 이미지)
    @objc func compareImages() {
        if let url1String = urlTextField1.text, let url2String = urlTextField2.text,
           let url1 = URL(string: url1String), let url2 = URL(string: url2String) {
            // URL을 이용한 이미지 비교
            imageComparator.compareBookImages(url1: url1, url2: url2) { similarity in
                self.updateResultLabel(similarity)
            }
        } else if let img1 = imageView1.image, let img2 = imageView2.image {
            // 로컬 이미지 비교
            imageComparator.compareBookImages(image1: img1, image2: img2) { similarity in
                self.updateResultLabel(similarity)
            }
        } else {
            resultLabel.text = "두 개의 책 표지를 선택하거나 URL을 입력하세요!"
        }
    }
    
    // MARK: - 결과 업데이트
    func updateResultLabel(_ similarity: Float?) {
        DispatchQueue.main.async {
            if let similarity = similarity {
                self.resultLabel.text = "유사도: \(String(format: "%.1f", similarity))%"
            } else {
                self.resultLabel.text = "유사도 비교 실패"
            }
        }
    }
}
