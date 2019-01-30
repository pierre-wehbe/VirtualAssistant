import AVFoundation
import UIKit
import Vision

class VisionViewController: CameraViewController {

    // Vision Queue
    private let visionQueue = DispatchQueue(label: "Vision")

    // Vision Requests
    private var analysisRequests = [VNRequest]() // requests that will be performed on the buffered image
    private let sequenceRequestHandler = VNSequenceRequestHandler() // to perform 1++ requests on a series of image

    // The current pixel buffer undergoing analysis. Run requests in a serial fashion, one after another.
    private var currentlyAnalyzedPixelBuffer: CVPixelBuffer?

    // Registration Variables
    private let MAXIMUM_HISTORY_LENGTH: Int = 15
    private let MANHATTAN_DISTANCE: CGFloat = 20.0
    private var transpositionHistoryPoints: [CGPoint] = []
    private var previousPixelBuffer: CVPixelBuffer? // this buffer store an image from Core Video in main memory

    // Overlays
    private var detectionOverlay: CALayer! = nil
    private var showingInformationOverlays: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func setupAVCapture() {
        super.setupAVCapture()

        // Setup Vision parts
        setupLayers()
        setupVision()

        // Start the capture
        startCaptureSession()
    }

    func setupLayers() {
        detectionOverlay = CALayer()
        detectionOverlay.bounds = self.view.bounds.insetBy(dx: 20, dy: 20)
        detectionOverlay.position = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
        detectionOverlay.borderColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.7])
        detectionOverlay.borderWidth = 8
        detectionOverlay.cornerRadius = 20
        detectionOverlay.isHidden = true
        self.view.layer.addSublayer(detectionOverlay)
    }

    @discardableResult
    func setupVision() -> NSError? {
        // Setup vision parts
        let error: NSError! = nil

        guard let modelURL = Bundle.main.url(forResource: "DemoClassifier", withExtension: "mlmodelc") else {
            return NSError(domain: "VisionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "The model file is missing."])
        }
        // Setup classification request
        guard let objectRecognition = createClassificationRequest(modelURL: modelURL) else {
            return NSError(domain: "VisionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "The classification request failed."])
        }
        self.analysisRequests.append(objectRecognition)
        return error
    }

    private func createClassificationRequest(modelURL: URL) -> VNCoreMLRequest? {
        do {
            let objectClassifier = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let classificationRequest = VNCoreMLRequest(model: objectClassifier) { (request, error) in
                if let results = request.results as? [VNClassificationObservation] {
                    print("\(results.first!.identifier) : \(results.first!.confidence)")
                    if results.first!.confidence > 0.9 {
                        print("Good to show")
                    }
                }
            }
            return classificationRequest
        } catch let error as NSError {
            print("Model failed to load: \(error).")
            return nil
        }
    }
}

// Anaylisis of current Image
extension VisionViewController {
    func analyzeCurrentImage() {
        let orientation = exifOrientationFromDeviceOrientation()

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentlyAnalyzedPixelBuffer!, orientation: orientation)
        visionQueue.async {
            do {
                defer { self.currentlyAnalyzedPixelBuffer = nil }
                try requestHandler.perform(self.analysisRequests)
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
}

// Checking for screen stability
extension VisionViewController {
    fileprivate func sceneStabilityAchieved() -> Bool {
        // If I have enough points
        if transpositionHistoryPoints.count >= MAXIMUM_HISTORY_LENGTH {
            // Calculate the moving average
            var movingAverage: CGPoint = CGPoint.zero
            for currentPoint in transpositionHistoryPoints {
                movingAverage.x += currentPoint.x
                movingAverage.y += currentPoint.y
            }
            let distance = abs(movingAverage.x) + abs(movingAverage.y) // manhattan distance
            if distance < MANHATTAN_DISTANCE {
                return true
            }
        }
        return false
    }

    fileprivate func resetTranspositionHistory() {
        transpositionHistoryPoints.removeAll()
    }

    fileprivate func recordTransposition(_ point: CGPoint) {
        transpositionHistoryPoints.append(point)

        if transpositionHistoryPoints.count > MAXIMUM_HISTORY_LENGTH {
            transpositionHistoryPoints.removeFirst()
        }
    }

    private func showDetectionOverlay(_ visible: Bool) {
        DispatchQueue.main.async(execute: {
            // Perform all the UI updates on the main queue
            self.detectionOverlay.isHidden = !visible
        })
    }
}

//MARK: AVCaptureVideoDataOutput SampleBuffer Delegate
extension VisionViewController {
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        guard previousPixelBuffer != nil else {
            previousPixelBuffer = pixelBuffer
            self.resetTranspositionHistory()
            return
        }

        if showingInformationOverlays {
            return
        }

        let registrationRequest = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: pixelBuffer) // want to compare previous to current
        do {
            try sequenceRequestHandler.perform([registrationRequest], on: previousPixelBuffer!)
        } catch let error as NSError {
            print("Failed to process request: \(error.localizedDescription).")
            return
        }

        previousPixelBuffer = pixelBuffer // update previous pixel

        if let results = registrationRequest.results {
            if let alignmentObservation = results.first as? VNImageTranslationAlignmentObservation {
                let alignmentTransform = alignmentObservation.alignmentTransform
                self.recordTransposition(CGPoint(x: alignmentTransform.tx, y: alignmentTransform.ty))
            }
        }

        if self.sceneStabilityAchieved() {
            self.showDetectionOverlay(true)
            if currentlyAnalyzedPixelBuffer == nil {
                currentlyAnalyzedPixelBuffer = pixelBuffer // initialize with latest pixel buffer image
                analyzeCurrentImage()
            }
        } else {
            self.showDetectionOverlay(false)
        }
    }
}
