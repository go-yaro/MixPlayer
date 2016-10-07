//
//  MixPlayer.swift
//  MixPlayer
//
//  Created by go.yaro on 10/6/16.
//  Copyright © 2016 DDDrop. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit
import Result
import ReactiveCocoa
import SnapKit

class MixPlayer : UIView {
    enum StatusType : String {
        case Loading        = "Loading"
        case Failed         = "Failed"
        case Playing        = "Playing"
        case Paused         = "Paused"
        case End            = "End"
    }

    // MARK: - Public Property
    var url : NSURL
    var autoReloading : Bool = true

    override var frame: CGRect {
        didSet {
            playerLayerView?.frame = frame
            playerLayer?.frame = frame
        }
    }
    var blackView = UIView()
    var liveIsFinished : Bool = false

    // MARK: - Private Property
    private var playerLayerView : UIView?
    private var playerLayer : AVPlayerLayer?
    private var playerItem : AVPlayerItem?
    private var player : AVPlayer?
    private var playerItemScreenshotOutput : AVPlayerItemVideoOutput?

    private var playerLayerAffineTransform : CGAffineTransform?

    private let logoImgView = UIImageView(image: UIImage(named: "logoMixCh"))
    private var indicator = UIActivityIndicatorView(activityIndicatorStyle: .WhiteLarge)

    private(set) var status = MutableProperty<StatusType>(.Loading)

    private var reloadInterval = 2
    private var reloadTimer : NSTimer?

    private var disposables = CompositeDisposable()

    private var enableToReload : Bool = true
    private var httpRequestEtag : String? {
        didSet (oldValue) {
            if oldValue == httpRequestEtag || status.value == .Playing {
                enableToReload = false
            } else {
                enableToReload = true
            }
        }
    }
    private var audioSession : AVAudioSession?


    // MARK: -

    // MARK: - Initialization
    init(url: NSURL) {
        self.url = url

        super.init(frame: CGRectZero)

        setup()
        setupPlayerStateMachine()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        player = AVPlayer()
        playerLayer = AVPlayerLayer()
        playerLayer?.player = player
        playerLayerView = UIView()
        playerLayerView?.layer.addSublayer(playerLayer!)
        addSubview(playerLayerView!)
        frame = UIScreen.mainScreen().bounds

        playerItemScreenshotOutput = AVPlayerItemVideoOutput()

        audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession?.setActive(true)
        } catch {
            print("AudioSession Error")
        }

        addSubview(logoImgView)
        blackView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        blackView.hidden = true
        addSubview(blackView)

        showIndicatorMain()
    }

    private func showIndicatorMain() {
        dispatch_async(dispatch_get_main_queue()) { [weak self] in
            self?.showIndicator()
        }
    }

    private func showIndicator() {
        if self.indicator.superview == nil {
            self.addSubview(self.indicator)
            self.indicator.snp_remakeConstraints(closure: { (make) in
                make.centerX.equalTo(self.snp_centerX)
                make.centerY.equalTo(self.snp_centerY)
            })
        } else {
            self.bringIndicatorFront()
        }
        if !self.indicator.isAnimating() {
            self.indicator.startAnimating()
        }
    }

    private func bringIndicatorFront() {
        if self.indicator.superview == self {
            self.bringSubviewToFront(self.indicator)
        }
    }

    private func dismissIndicator() {
        if self.indicator.isAnimating() {
            self.indicator.stopAnimating()
            self.sendSubviewToBack(self.indicator)
        }
    }

    private func setupPlayerStateMachine() {
        disposables += timer(2, onScheduler: QueueScheduler()).startWithNext({ [weak self] _ in
            if let wself = self {
                wself.getLiveHttpRequestEtag(wself.url)
                print("ETAG: \(wself.httpRequestEtag) | EL: \(wself.enableToReload) | ST: \(wself.status.value.rawValue)")
                let likelyToKeepUp = wself.playerItem?.playbackLikelyToKeepUp ?? false
                let playItemStatus = wself.playerItem?.status ?? .Unknown

                switch wself.status.value {
                case .Loading :
                    if likelyToKeepUp && playItemStatus == .ReadyToPlay && wself.enableToReload {
                        wself.player?.play()
                        wself.status.swap(.Playing)
                    } else {
                        wself.loadPlayerItem()
                    }
                case .Failed :
                    break
                case .Playing :
                    if !likelyToKeepUp {
                        wself.status.swap(.Loading)
                    }
                case .Paused :
                    break
                case .End :
                    break
                }
            }
        })
    }

    func loadPlayerItem() {
        status.swap(.Loading)
        guard enableToReload else {
            return
        }

        print("relaoded")
        NSNotificationCenter.defaultCenter().removeObserver(self)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(sessionDidInterrupt), name: AVAudioSessionRouteChangeNotification, object: nil)

        playerItem = AVPlayerItem(URL: url)
        playerItem?.addOutput(playerItemScreenshotOutput!)

        player?.replaceCurrentItemWithPlayerItem(playerItem)

        if playerItem != nil {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(loadPlayerItem), name:
                AVPlayerItemFailedToPlayToEndTimeNotification, object: playerItem!)
        }
    }

    func sessionDidInterrupt() {
        player?.pause()
        status.swap(.Loading)
    }

    private func getLiveHttpRequestEtag(url: NSURL) {
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "GET"
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {[weak self] (data, response, error) in
            if error == nil {
                if let httpResponse = response as? NSHTTPURLResponse {
                    if let etag = httpResponse.allHeaderFields["etag"] as? String {
                        self?.httpRequestEtag = etag
                    }
                }
            }
        }
        task.resume()
    }

    // MARK: - UI
    override func updateConstraints() {
        super.updateConstraints()
        playerLayerView?.snp_remakeConstraints { (make) in
            make.edges.equalTo(self)
        }
        logoImgView.snp_remakeConstraints { (make) in
            make.centerX.equalTo(self.snp_centerX)
            make.top.equalTo(self.frame.height*0.4)
        }
        blackView.snp_remakeConstraints { (make) in
            make.size.equalTo(self)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = playerLayerView?.frame ?? CGRectZero
        playerLayer?.bounds = playerLayerView?.bounds ?? CGRectZero
        if playerLayerAffineTransform == nil {
            playerLayerAffineTransform = playerLayer?.affineTransform()
        }
        if UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation) {
            let tmp = CGAffineTransformRotate(CGAffineTransformIdentity, CGFloat(M_PI_2))
            let scale = CGAffineTransformScale(tmp, 1280.0/720.0, 1280.0/720.0)
            playerLayer?.setAffineTransform(scale)
            logoImgView.snp_remakeConstraints { (make) in
                make.centerX.equalTo(self.snp_centerX)
                make.top.equalTo(self.frame.height*0.3)
            }
        } else {
            playerLayer?.setAffineTransform(CGAffineTransformIdentity)
            logoImgView.snp_remakeConstraints { (make) in
                make.centerX.equalTo(self.snp_centerX)
                make.top.equalTo(self.frame.height*0.3)
            }
        }
    }

    // MARK: - Public Function
    func play() {
        if status.value == .Playing {
            return
        }
        if status.value == .Paused {
            status.swap(.Playing)
            player?.play()
        }
    }

    func pause() {
        if status.value == .Playing {
            status.swap(.Paused)
            player?.pause()
        }
    }

    func reload() {
        status.swap(.Loading)
    }

    func screenShotFromPlayer() -> UIImage? {
        if status.value != .Playing {
            return nil
        }
        if let itemTime = playerItem?.currentTime() {
            if let pixelBuffer = playerItemScreenshotOutput?.copyPixelBufferForItemTime(itemTime, itemTimeForDisplay: nil) {
                CVPixelBufferLockBaseAddress(pixelBuffer, 0)
                let ciImage = CIImage(CVPixelBuffer: pixelBuffer)
                CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
                let tempContext = CIContext(options: nil)
                let cgImage = tempContext.createCGImage(ciImage, fromRect: CGRectMake(0, 0, CGFloat(CVPixelBufferGetWidth(pixelBuffer)), CGFloat(CVPixelBufferGetHeight(pixelBuffer))))
                if UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation) {
                    return UIImage(CGImage: cgImage, scale: UIScreen.mainScreen().bounds.width/720, orientation: .Right)
                } else {
                    return UIImage(CGImage: cgImage, scale: UIScreen.mainScreen().bounds.width/720, orientation: .Up)
                }
            }
        }
        return nil
    }
}