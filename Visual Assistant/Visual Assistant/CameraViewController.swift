import AVKit
import UIKit

class CameraViewController: UIViewController {

    private let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue.init(label: "VideoDataOutput",
                                                qos: .userInitiated,
                                                attributes: [],
                                                autoreleaseFrequency: .workItem)

    private var previewLayer: AVCaptureVideoPreviewLayer! = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAVCapture()
    }

    func setupAVCapture() {
        var deviceInput: AVCaptureDeviceInput!

        // Find video camera in set it as input
        guard let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                           mediaType: .video,
                                                           position: .back)
            .devices.first else { return }
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Couldn't create video device input: \(error)")
            return
        }

        // Configure Session
        session.beginConfiguration()

        // Since the model input size in 299x299 then
        session.sessionPreset = .vga640x480

        // Add input
        guard session.canAddInput(deviceInput) else {
            print("Could not add video device input to the session.")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput) // add video input to session

        // Add output
        guard session.canAddOutput(videoDataOutput) else {
            print("Could not add video device output to the session.")
            session.commitConfiguration()
            return
        }
        session.addOutput(videoDataOutput)

        videoDataOutput.alwaysDiscardsLateVideoFrames = true // when frames are blocked in capture output
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)

        let captureConnection = videoDataOutput.connection(with: .video)
        captureConnection?.isEnabled = true // always process the frames

        session.commitConfiguration() // done configuring session

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = self.view.layer.bounds
        self.view.layer.insertSublayer(previewLayer, at: 0)
    }

    func startCaptureSession() {
        session.startRunning()
    }

    func tearDownAVCapture() {
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }

    public func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // device oriented vertically, Home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // device oriented horizontally, Home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // device oriented horizontally, Home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // device oriented vertically, Home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
}

//MARK: AVCaptureVideoDataOutput SampleBuffer Delegate
extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Will implement in child viewcontroller (subclass)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Dropped frames
    }
}
