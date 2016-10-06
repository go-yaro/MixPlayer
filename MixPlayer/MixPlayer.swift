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

class MixPlayer : UIView {
    enum StatusType : String {
        case Initializing   = "Initializing"
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

    // MARK: - Private Property
    private var playerLayerView : UIView?
    private var playerLayer : AVPlayerLayer?
    private var playerItem : AVPlayerItem?
    private var player : AVPlayer?
    private var playerItemScreenshotOutput : AVPlayerItemVideoOutput?

    private var playerLayerAffineTransform : CGAffineTransform?

    private(set) var status = MutableProperty<StatusType>(.Initializing)

    private var reloadInterval = 2
    private var reloadTimer : NSTimer?

    private var disposables = CompositeDisposable()

    private var enableToReload : Bool = true
    private var httpRequestEtag : String? {
        didSet (oldValue) {
            if oldValue == httpRequestEtag {
                enableToReload = false
            } else {
                enableToReload = true
            }
        }
    }

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

        loadPlayerItem()
    }

    private func setupPlayerStateMachine() {
        disposables += timer(1, onScheduler: QueueScheduler()).startWithNext({ [weak self] _ in
            if let wself = self {
                wself.getLiveHttpRequestEtag(wself.url)
                let likelyToKeepUp = wself.playerItem?.playbackLikelyToKeepUp ?? false
                let playItemStatus = wself.playerItem?.status ?? .Unknown

                switch wself.status.value {
                case .Initializing :
                    break
                case .Loading :
                    if likelyToKeepUp {
                        wself.player?.play()
                        wself.status.swap(.Playing)
                    } else if playItemStatus == .Failed || !likelyToKeepUp {
                        wself.loadPlayerItem()
                    }
                case .Failed :
                    break
                case .Playing :
                    break
                case .Paused :
                    break
                case .End :
                    break
                }
            }
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }

    func loadPlayerItem() {
        guard !enableToReload else {
            return
        }

        NSNotificationCenter.defaultCenter().removeObserver(self)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(sessionDidInterrupt), name: AVAudioSessionRouteChangeNotification, object: nil)

        playerItem = AVPlayerItem(URL: url)
        playerItem?.addOutput(playerItemScreenshotOutput!)

        player?.replaceCurrentItemWithPlayerItem(playerItem)

        if playerItem != nil {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(loadPlayerItem), name:
                AVPlayerItemFailedToPlayToEndTimeNotification, object: playerItem!)
        }

        status.swap(.Loading)
    }

    func sessionDidInterrupt() {

    }

    private func getLiveHttpRequestEtag(url: NSURL) {
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "GET"
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {[weak self] (data, response, error) in
            if error == nil {
                if let httpResponse = response as? NSHTTPURLResponse {
                    if let etag = httpResponse.allHeaderFields["etag"] as? String {
                        self?.httpRequestEtag = etag
                        print(etag)
                    }
                }
            }
        }
        task.resume()
    }
}