// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "headless_ar_measure",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "headless-ar-measure", targets: ["headless_ar_measure"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "headless_ar_measure",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // Dòng này KHÔNG được để chú thích. Khuôn `flutter create` sinh
                // ra nó dưới dạng chú thích, và cả hai gói cùng nhà đều để
                // nguyên như thế — nên gói nào bật Swift Package Manager là
                // ship THIẾU bản kê khai quyền riêng tư mà không có lỗi nào nổ:
                // đường CocoaPods vẫn chở tệp qua `s.resource_bundles` bên
                // podspec, nên bản dựng bằng pod trông hoàn toàn bình thường và
                // chỉ bản dựng SPM là hụt.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
