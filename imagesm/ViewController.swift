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
    let compareButton = UIButton()
    let resultLabel = UILabel()
    var selectedImageView: UIImageView?
    
    // ✅ BookImageComparator 인스턴스 생성
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
        
        compareButton.setTitle("비교하기", for: .normal)
        compareButton.setTitleColor(.white, for: .normal)
        compareButton.backgroundColor = .systemBlue
        compareButton.addTarget(self, action: #selector(compareImages), for: .touchUpInside)
        
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 2
        resultLabel.text = "책 표지를 비교하려면 이미지를 선택하세요."
        
        let stackView = UIStackView(arrangedSubviews: [imageView1, imageView2, compareButton, resultLabel])
        stackView.axis = .vertical
        stackView.spacing = 20
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

        if let selectedImage = info[.originalImage] as? UIImage {
            selectedImageView?.image = selectedImage
        }
    }

    // MARK: - 이미지 비교 실행
    @objc func compareImages() {
        guard let img1 = imageView1.image, let img2 = imageView2.image else {
            resultLabel.text = " 두 개의 책 표지를 선택하세요!"
            return
        }

        // 인스턴스를 통해 메서드 호출
        imageComparator.compareBookImages(image1: img1, image2: img2) { similarity in
            DispatchQueue.main.async {
                if let similarity = similarity {
                    self.resultLabel.text = " 유사도: \(String(format: "%.1f", similarity))%"
                } else {
                    self.resultLabel.text = " 유사도 비교 실패"
                }
            }
        }
    }
}
