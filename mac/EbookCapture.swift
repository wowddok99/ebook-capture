import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct CaptureRegion {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var displayName: String?

    var screencaptureArgument: String {
        "\(x),\(y),\(width),\(height)"
    }
}

final class RegionSelectionView: NSView {
    private var start: NSPoint?
    private var current: NSPoint?
    private let desktopFrame: NSRect
    private let screens: [NSScreen]
    var onFinish: ((CaptureRegion) -> Void)?
    var onCancel: (() -> Void)?

    init(frame: NSRect, desktopFrame: NSRect, screens: [NSScreen]) {
        self.desktopFrame = desktopFrame
        self.screens = screens
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        self.desktopFrame = .zero
        self.screens = []
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.05, alpha: 0.45).setFill()
        bounds.fill()

        let help = "캡처할 영역을 드래그하세요. 취소: ESC"
        help.draw(
            at: NSPoint(x: 28, y: bounds.height - 54),
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor.white,
            ]
        )

        guard let start, let current else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        NSColor.systemPink.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 4
        path.stroke()

        let captureRegion = captureRegion(from: rect)
        let text = "x=\(captureRegion.x), y=\(captureRegion.y), w=\(captureRegion.width), h=\(captureRegion.height)"
        text.draw(
            at: NSPoint(x: 28, y: bounds.height - 88),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.systemPink,
            ]
        )
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        guard rect.width >= 10, rect.height >= 10 else { return }

        onFinish?(captureRegion(from: rect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    private func captureRegion(from rect: NSRect) -> CaptureRegion {
        let appKitRect = rect.offsetBy(dx: desktopFrame.minX, dy: desktopFrame.minY)
        let center = NSPoint(x: appKitRect.midX, y: appKitRect.midY)
        guard let screen = screens.first(where: { $0.frame.contains(center) }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return CaptureRegion(
                x: Int(appKitRect.minX.rounded()),
                y: Int((desktopFrame.maxY - appKitRect.maxY).rounded()),
                width: Int(appKitRect.width.rounded()),
                height: Int(appKitRect.height.rounded()),
                displayName: "unknown"
            )
        }

        let displayBounds = CGDisplayBounds(displayID)
        let x = displayBounds.minX + (appKitRect.minX - screen.frame.minX)
        let y = displayBounds.minY + (screen.frame.maxY - appKitRect.maxY)

        return CaptureRegion(
            x: Int(x.rounded()),
            y: Int(y.rounded()),
            width: Int(appKitRect.width.rounded()),
            height: Int(appKitRect.height.rounded()),
            displayName: screen.localizedName
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let repositoryURLString = "https://github.com/wowddok99/ebook-capture"
    private var window: NSWindow!
    private var selectionWindow: NSWindow?
    private var outputField: NSTextField!
    private var maxPagesLabel: NSTextField!
    private var maxPagesField: NSTextField!
    private var delayField: NSTextField!
    private var modePopup: NSPopUpButton!
    private var startPageLabel: NSTextField!
    private var startPageField: NSTextField!
    private var endPageLabel: NSTextField!
    private var endPageField: NSTextField!
    private var xField: NSTextField!
    private var yField: NSTextField!
    private var wField: NSTextField!
    private var hField: NSTextField!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var region: CaptureRegion?
    private var stopRequested = false
    private var isCapturing = false
    private var selectionKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        requestScreenCapturePermissionIfNeeded()
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Ebook Capture"
        window.isReleasedWhenClosed = false

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        addLabel("Ebook Capture", x: 24, y: 502, width: 300, height: 32, size: 24, bold: true)
        addLabel("저장 경로", x: 24, y: 444, width: 100, height: 24)
        outputField = addTextField(NSHomeDirectory() + "/Desktop/ebook-pages", x: 128, y: 438, width: 500)
        addButton("선택", x: 646, y: 436, width: 90, action: #selector(chooseOutput))

        maxPagesLabel = addLabel("최대 페이지", x: 24, y: 394, width: 100, height: 24)
        maxPagesField = addTextField("300", x: 128, y: 388, width: 110)
        addLabel("이동 대기(초)", x: 284, y: 394, width: 120, height: 24)
        delayField = addTextField("0.8", x: 408, y: 388, width: 110)
        addLabel("모드", x: 548, y: 394, width: 44, height: 24)
        modePopup = NSPopUpButton(frame: NSRect(x: 594, y: 386, width: 142, height: 32), pullsDown: false)
        modePopup.addItems(withTitles: ["자동 종료", "페이지 범위"])
        modePopup.target = self
        modePopup.action = #selector(captureModeChanged)
        content.addSubview(modePopup)

        startPageLabel = addLabel("첫 페이지", x: 24, y: 344, width: 100, height: 24)
        startPageField = addTextField("1", x: 128, y: 338, width: 110)
        endPageLabel = addLabel("끝 페이지", x: 284, y: 344, width: 100, height: 24)
        endPageField = addTextField("300", x: 408, y: 338, width: 110)

        addButton("영역 드래그 선택", x: 24, y: 290, width: 170, action: #selector(selectRegion))
        addButton("테스트 캡처", x: 210, y: 290, width: 150, action: #selector(testCapture))
        addButton("캡처 시작", x: 376, y: 290, width: 150, action: #selector(startCapture))
        addButton("중지", x: 542, y: 290, width: 110, action: #selector(stopCapture))
        addButton("화면 기록 권한 열기", x: 24, y: 20, width: 170, action: #selector(openScreenRecordingSettings))
        addButton("손쉬운 사용 권한 열기", x: 210, y: 20, width: 180, action: #selector(openAccessibilitySettings))
        addLinkButton("github.com/wowddok99/ebook-capture", x: 430, y: 20, width: 306, action: #selector(openGitHub))

        addLabel("영역 수치", x: 24, y: 238, width: 100, height: 24)
        addLabel("x", x: 128, y: 238, width: 18, height: 24, size: 13, bold: true)
        xField = addTextField("0", x: 148, y: 232, width: 82)
        addLabel("y", x: 244, y: 238, width: 18, height: 24, size: 13, bold: true)
        yField = addTextField("0", x: 264, y: 232, width: 82)
        addLabel("w", x: 360, y: 238, width: 18, height: 24, size: 13, bold: true)
        wField = addTextField("0", x: 380, y: 232, width: 82)
        addLabel("h", x: 476, y: 238, width: 18, height: 24, size: 13, bold: true)
        hField = addTextField("0", x: 496, y: 232, width: 82)
        addButton("수치 적용", x: 600, y: 230, width: 136, action: #selector(applyRegionNumbers))

        let line = NSBox(frame: NSRect(x: 24, y: 198, width: 712, height: 1))
        line.boxType = .separator
        content.addSubview(line)

        statusLabel = addLabel("캡처 영역을 먼저 선택하세요.", x: 24, y: 160, width: 712, height: 28)
        detailLabel = addLabel("저장 경로: \(outputField.stringValue)\n선택 영역: 미선택\n진행: 대기 중", x: 24, y: 72, width: 712, height: 78, size: 13)
        detailLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        captureModeChanged()
    }

    @objc private func captureModeChanged() {
        let usesMaxPages = modePopup.indexOfSelectedItem == 0
        let usesPageRange = !usesMaxPages
        maxPagesField.isEnabled = usesMaxPages
        maxPagesLabel.textColor = usesMaxPages ? .labelColor : .secondaryLabelColor
        startPageField.isEnabled = usesPageRange
        endPageField.isEnabled = usesPageRange
        startPageLabel.textColor = usesPageRange ? .labelColor : .secondaryLabelColor
        endPageLabel.textColor = usesPageRange ? .labelColor : .secondaryLabelColor
    }

    private func requestScreenCapturePermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            statusLabel.stringValue = "화면 기록 권한이 필요합니다. 권한 허용 후 앱을 다시 실행하세요."
            _ = CGRequestScreenCaptureAccess()
            openScreenRecordingSettings()
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        if !isAccessibilityTrusted(prompt: true) {
            statusLabel.stringValue = "키보드 자동 입력 권한이 필요합니다. 손쉬운 사용에서 EbookCapture를 허용하고 다시 실행하세요."
            openAccessibilitySettings()
        }
    }

    @objc private func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc private func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc private func openGitHub() {
        if let url = URL(string: repositoryURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, size: CGFloat = 14, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: width, height: height)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        window.contentView?.addSubview(label)
        return label
    }

    private func addTextField(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let field = NSTextField(string: text)
        field.frame = NSRect(x: x, y: y, width: width, height: 28)
        field.font = .systemFont(ofSize: 14)
        window.contentView?.addSubview(field)
        return field
    }

    private func addButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = NSRect(x: x, y: y, width: width, height: 34)
        button.bezelStyle = .rounded
        window.contentView?.addSubview(button)
    }

    private func addLinkButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) {
        let button = NSButton(title: "", target: self, action: action)
        button.frame = NSRect(x: x, y: y, width: width, height: 34)
        button.isBordered = false
        button.bezelStyle = .inline
        button.alignment = .right
        button.toolTip = repositoryURLString
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        window.contentView?.addSubview(button)
    }

    @objc private func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            outputField.stringValue = url.path
            updateDetails(progress: nil)
        }
    }

    @objc private func selectRegion() {
        window.orderOut(nil)
        let desktopFrame = NSScreen.screens.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        let screenFrame = desktopFrame.isNull ? NSRect(x: 0, y: 0, width: 1440, height: 900) : desktopFrame
        let view = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            desktopFrame: screenFrame,
            screens: NSScreen.screens
        )
        let overlay = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlay.level = .screenSaver
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.isReleasedWhenClosed = false
        overlay.contentView = view
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
        selectionWindow = overlay
        selectionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelRegionSelection()
                return nil
            }
            return event
        }
        view.onFinish = { [weak self] selected in
            DispatchQueue.main.async {
                self?.finishRegionSelection()
                self?.setRegion(selected)
            }
        }
        view.onCancel = { [weak self] in
            DispatchQueue.main.async {
                self?.cancelRegionSelection()
            }
        }
    }

    private func finishRegionSelection() {
        if let selectionKeyMonitor {
            NSEvent.removeMonitor(selectionKeyMonitor)
            self.selectionKeyMonitor = nil
        }
        selectionWindow?.orderOut(nil)
        selectionWindow = nil
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cancelRegionSelection() {
        finishRegionSelection()
        statusLabel.stringValue = "영역 선택을 취소했습니다."
    }

    private func setRegion(_ selected: CaptureRegion) {
        region = selected
        xField.stringValue = "\(selected.x)"
        yField.stringValue = "\(selected.y)"
        wField.stringValue = "\(selected.width)"
        hField.stringValue = "\(selected.height)"
        statusLabel.stringValue = "선택 영역: \(regionSummary(selected))"
        updateDetails(progress: nil)
    }

    @objc private func applyRegionNumbers() {
        let selected = CaptureRegion(
            x: xField.integerValue,
            y: yField.integerValue,
            width: wField.integerValue,
            height: hField.integerValue
        )
        guard selected.width >= 10, selected.height >= 10 else {
            statusLabel.stringValue = "w/h는 10 이상이어야 합니다."
            return
        }
        setRegion(selected)
        statusLabel.stringValue = "입력한 수치를 캡처 영역으로 적용했습니다."
    }

    @objc private func testCapture() {
        guard let region else {
            statusLabel.stringValue = "먼저 캡처 영역을 선택하세요."
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            statusLabel.stringValue = "화면 기록 권한이 없습니다. 시스템 설정에서 EbookCapture를 허용하고 다시 실행하세요."
            _ = CGRequestScreenCaptureAccess()
            openScreenRecordingSettings()
            return
        }
        let outputPath = outputField.stringValue
        statusLabel.stringValue = "2초 후 테스트 캡처합니다. 전자책 뷰어 창을 클릭하세요."
        updateDetails(progress: "2초 후 테스트 캡처")
        window.orderOut(nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Thread.sleep(forTimeInterval: 2)
            self?.runTestCapture(region: region, outputPath: outputPath)
        }
    }

    private func runTestCapture(region: CaptureRegion, outputPath: String) {
        do {
            let output = try ensureOutputDirectory(outputPath)
            let target = output.appendingPathComponent("test_capture.png")
            try captureScreen(region: region, to: target)
            DispatchQueue.main.async {
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.statusLabel.stringValue = "테스트 캡처 저장 완료: \(target.path)"
                self.updateDetails(progress: "테스트 캡처 저장 완료, 파일: test_capture.png")
            }
        } catch {
            DispatchQueue.main.async {
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.statusLabel.stringValue = "테스트 캡처 실패: \(error.localizedDescription)"
            }
        }
    }

    @objc private func startCapture() {
        guard !isCapturing else { return }
        guard let region else {
            statusLabel.stringValue = "먼저 캡처 영역을 선택하세요."
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            statusLabel.stringValue = "화면 기록 권한이 없습니다. 시스템 설정에서 EbookCapture를 허용하고 다시 실행하세요."
            _ = CGRequestScreenCaptureAccess()
            openScreenRecordingSettings()
            return
        }
        guard isAccessibilityTrusted(prompt: true) else {
            statusLabel.stringValue = "키보드 자동 입력 권한이 없습니다. 손쉬운 사용에서 EbookCapture를 허용하고 다시 실행하세요."
            openAccessibilitySettings()
            return
        }
        isCapturing = true
        stopRequested = false
        statusLabel.stringValue = "3초 후 시작합니다. 선택 영역의 전자책 창이 페이지 넘김 대상이 됩니다."
        updateDetails(progress: "3초 후 시작, 선택 영역 기준 대상 앱 확인")
        let outputPath = outputField.stringValue
        let maxPages = max(1, maxPagesField.integerValue)
        let delay = max(0.1, delayField.doubleValue)
        let isRangeMode = modePopup.indexOfSelectedItem == 1
        let startPage = max(1, startPageField.integerValue)
        let endPage = max(startPage, endPageField.integerValue)
        let runName = DateFormatter.captureRun.string(from: Date())
        window.orderOut(nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureLoop(
                region: region,
                outputPath: outputPath,
                delay: delay,
                startPage: isRangeMode ? startPage : 1,
                endPage: isRangeMode ? endPage : maxPages,
                stopOnDuplicate: !isRangeMode,
                runName: runName
            )
        }
    }

    @objc private func stopCapture() {
        stopRequested = true
        statusLabel.stringValue = "중지 요청됨. 현재 캡처가 끝나면 멈춥니다."
    }

    private func captureLoop(
        region: CaptureRegion,
        outputPath: String,
        delay: Double,
        startPage: Int,
        endPage: Int,
        stopOnDuplicate: Bool,
        runName: String
    ) {
        Thread.sleep(forTimeInterval: 3)
        var shouldShowRepositoryPrompt = false

        do {
            let targetPid = try pageTurnTargetProcessIdentifier(
                for: region,
                excluding: ProcessInfo.processInfo.processIdentifier
            )
            let output = try ensureOutputDirectory(outputPath).appendingPathComponent(runName)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var previousHash: String?
            var captured = 0
            var duplicateDetected = false

            let totalPages = endPage - startPage + 1
            for (offset, page) in (startPage...endPage).enumerated() {
                if stopRequested { break }
                let filename = String(format: "page_%04d.png", page)
                let target = output.appendingPathComponent(filename)
                updateMain(progress: "\(offset + 1)/\(totalPages) 캡처 중, 저장 파일: \(filename)")
                try captureScreen(region: region, to: target)

                let hash = try sha256(target)
                if stopOnDuplicate, let previousHash, previousHash == hash {
                    try? FileManager.default.removeItem(at: target)
                    duplicateDetected = true
                    updateMain(status: "같은 화면이 감지되어 종료했습니다. 저장된 페이지: \(captured)", progress: "종료, 저장된 페이지 \(captured)개")
                    break
                }
                previousHash = hash
                captured += 1

                if page < endPage {
                    try pressRightArrow(to: targetPid)
                    Thread.sleep(forTimeInterval: delay)
                }
            }

            if stopRequested {
                updateMain(status: "중지됨. 저장된 페이지: \(captured), 경로: \(output.path)", progress: "중지됨, 저장된 페이지 \(captured)개")
            } else if !duplicateDetected {
                updateMain(status: "완료. 저장된 페이지: \(captured), 경로: \(output.path)", progress: "완료, 저장된 페이지 \(captured)개")
            }
            shouldShowRepositoryPrompt = !stopRequested
        } catch {
            updateMain(status: "캡처 실패: \(error.localizedDescription)", progress: "오류")
        }

        DispatchQueue.main.async {
            self.isCapturing = false
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if shouldShowRepositoryPrompt {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.openRepositoryAndPromptForStar()
                }
            }
        }
    }

    private func openRepositoryAndPromptForStar() {
        openRepositoryURL()

        let alert = NSAlert()
        alert.messageText = "캡처가 완료되었습니다."
        alert.informativeText = "이 프로젝트가 유용했다면 GitHub Star로 응원해주세요."
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    private func openRepositoryURL() {
        if let url = URL(string: repositoryURLString), NSWorkspace.shared.open(url) {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [repositoryURLString]
        try? process.run()
    }

    private func ensureOutputDirectory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func updateMain(status: String? = nil, progress: String) {
        DispatchQueue.main.async {
            if let status {
                self.statusLabel.stringValue = status
            }
            self.updateDetails(progress: progress)
        }
    }

    private func updateDetails(progress: String?) {
        let regionText: String
        if let region {
            regionText = "선택 영역: \(regionSummary(region))"
        } else {
            regionText = "선택 영역: 미선택"
        }
        let progressText = progress ?? detailLabel?.stringValue.components(separatedBy: "\n").last?.replacingOccurrences(of: "진행: ", with: "") ?? "대기 중"
        detailLabel.stringValue = "저장 경로: \(outputField.stringValue)\n\(regionText)\n진행: \(progressText)"
    }

    private func regionSummary(_ region: CaptureRegion) -> String {
        let displayText = region.displayName.map { ", display=\($0)" } ?? ""
        return "x=\(region.x), y=\(region.y), w=\(region.width), h=\(region.height)\(displayText)"
    }
}

func runProcess(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw NSError(domain: "ProcessError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(executable) failed"])
    }
}

func captureScreen(region: CaptureRegion, to url: URL) throws {
    try runProcess("/usr/sbin/screencapture", ["-x", "-R", region.screencaptureArgument, url.path])
}

func isAccessibilityTrusted(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func pageTurnTargetProcessIdentifier(for region: CaptureRegion, excluding currentPid: pid_t) throws -> pid_t {
    if let regionPid = processIdentifierForWindow(containing: region, excluding: currentPid) {
        return regionPid
    }
    return try frontmostProcessIdentifier(excluding: currentPid)
}

func processIdentifierForWindow(containing region: CaptureRegion, excluding currentPid: pid_t) -> pid_t? {
    let center = CGPoint(
        x: CGFloat(region.x) + CGFloat(region.width) / 2,
        y: CGFloat(region.y) + CGFloat(region.height) / 2
    )
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }

    for window in windows {
        let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber
        let layerNumber = window[kCGWindowLayer as String] as? NSNumber
        let alphaNumber = window[kCGWindowAlpha as String] as? NSNumber
        guard let pid = pidNumber?.int32Value,
              pid != currentPid,
              layerNumber?.intValue == 0,
              alphaNumber?.doubleValue ?? 1 > 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let xNumber = bounds["X"] as? NSNumber,
              let yNumber = bounds["Y"] as? NSNumber,
              let widthNumber = bounds["Width"] as? NSNumber,
              let heightNumber = bounds["Height"] as? NSNumber else {
            continue
        }

        let x = CGFloat(xNumber.doubleValue)
        let y = CGFloat(yNumber.doubleValue)
        let width = CGFloat(widthNumber.doubleValue)
        let height = CGFloat(heightNumber.doubleValue)
        if CGRect(x: x, y: y, width: width, height: height).contains(center) {
            return pid_t(pid)
        }
    }

    return nil
}

func frontmostProcessIdentifier(excluding currentPid: pid_t) throws -> pid_t {
    guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != currentPid else {
        throw NSError(
            domain: "TargetAppError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "대상 전자책 앱을 찾을 수 없습니다. 캡처 영역을 전자책 창 위로 지정하거나 캡처 시작 후 3초 안에 전자책 창을 클릭하세요."]
        )
    }
    return app.processIdentifier
}

func pressRightArrow(to pid: pid_t) throws {
    guard isAccessibilityTrusted(prompt: false) else {
        throw NSError(
            domain: "AccessibilityError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "키보드 자동 입력 권한이 없습니다. 손쉬운 사용에서 EbookCapture를 허용하고 다시 실행하세요."]
        )
    }

    let rightArrowKeyCode = CGKeyCode(124)
    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: false) else {
        throw NSError(
            domain: "KeyboardEventError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "오른쪽 화살표 키 이벤트를 만들 수 없습니다."]
        )
    }

    keyDown.flags = []
    keyUp.flags = []
    keyDown.postToPid(pid)
    keyUp.postToPid(pid)
}

func sha256(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

extension DateFormatter {
    static let captureRun: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
