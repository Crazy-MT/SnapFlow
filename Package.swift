// swift-tools-version:5.3
import PackageDescription

// 本仓库是一个 macOS 应用（SnapFlowExample），不再作为可复用的快捷键库对外发布。
// Sources/SnapFlowKit 里的快捷键代码是应用运行所需的内部实现，保留为一个内部 target，
// 以便 `swift build` 能单独编译这部分逻辑。应用本身通过 SnapFlow.xcodeproj 构建。
let package = Package(
	name: "SnapFlowKit",
	platforms: [
		.macOS(.v10_11)
	],
	targets: [
		.target(
			name: "SnapFlowKit"
		)
	]
)
