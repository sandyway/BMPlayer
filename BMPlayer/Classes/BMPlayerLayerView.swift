//
//  BMPlayerLayerView.swift
//  Pods
//
//  Created by BrikerMan on 16/4/28.
//
//

import UIKit
import AVFoundation

public protocol BMPlayerLayerViewDelegate : class {
    func bmPlayer(player: BMPlayerLayerView ,playerStateDidChange state: BMPlayerState)
    func bmPlayer(player: BMPlayerLayerView ,loadedTimeDidChange  loadedDuration: TimeInterval , totalDuration: TimeInterval)
    func bmPlayer(player: BMPlayerLayerView ,playTimeDidChange    currentTime   : TimeInterval , totalTime: TimeInterval)
    func bmPlayer(player: BMPlayerLayerView ,playerIsPlaying      playing: Bool)
}

open class BMPlayerLayerView: UIView {
    
    open weak var delegate: BMPlayerLayerViewDelegate?
    
    /// 视频URL
    open var videoURL: URL! {
        didSet { onSetVideoURL() }
    }
    
    /// 视频跳转秒数置0
    open var seekTime = 0
    
    open var videoGravity = AVLayerVideoGravityResizeAspect {
        didSet {
            self.playerLayer?.videoGravity = videoGravity
        }
    }
    
    var aspectRatio:BMPlayerAspectRatio = .default {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    /// 计时器
    var timer       : Timer?
    
    /// 播放属性
//    lazy var _player: AVPlayer? = {
//        if let item = self.playerItem {
//            let player = AVPlayer(playerItem: item)
//            return player
//        }
//        return nil
//    }()
    
    var player: AVPlayer? {
        didSet {
            print("")
        }
    }
    
    
    open var isPlaying: Bool{
        
        get {
            if let player = player {
                return player.rate > 0.0
            }
            return false
        }
    }
    
    open var currentTime:TimeInterval {
        get {
            if let player = self.player {
                return CMTimeGetSeconds(player.currentTime())
            }
            return 0
        }
    }
    
    /// 播放属性
    open var playerItem: AVPlayerItem? {
        didSet {
            onPlayerItemChange()
        }
    }
    
    fileprivate var timeObserver: Any?
    
    fileprivate var lastPlayerItem: AVPlayerItem?
    /// playerLayer
    fileprivate var playerLayer: AVPlayerLayer?
    /// 音量滑杆
    fileprivate var volumeViewSlider: UISlider!
    /// 播发器的几种状态
    fileprivate var state = BMPlayerState.notSetURL {
        didSet {
            if state != oldValue || state == .buffering {
                print("state: \(state)")
                delegate?.bmPlayer(player: self, playerStateDidChange: state)
            }
        }
    }
    /// 是否为全屏
    fileprivate var isFullScreen  = false
    /// 是否锁定屏幕方向
    fileprivate var isLocked      = false
    /// 是否在调节音量
    fileprivate var isVolume      = false
    /// 是否播放本地文件
    fileprivate var isLocalVideo  = false
    /// slider上次的值
    fileprivate var sliderLastValue:Float = 0
    /// 是否点了重播
    fileprivate var repeatToPlay  = false
    /// 播放完了
    fileprivate var playDidEnd    = false
    // playbackBufferEmpty会反复进入，因此在bufferingOneSecond延时播放执行完之前再调用bufferingSomeSecond都忽略
    // 仅在bufferingSomeSecond里面使用
    fileprivate var isBuffering     = false
    
    
    // MARK: - Actions
    open func play() {
        if let player = player {
//            if isPlaying {return}
//            isPlaying = true
            player.play()
            timer?.fireDate = Date()
        }
    }
    
    
    open func pause() {
//        if !isPlaying {return}
//        isPlaying = false
        player?.pause()
        timer?.fireDate = Date.distantFuture
    }
    
    // MARK: - 生命周期
    /**
     *  初始化player
     */
    func initializeThePlayer() {
        // TODO: 10
        // 每次播放视频都解锁屏幕锁定
        //        [self unLockTheScreen];
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        BMPlayerManager.shared.log("BMPlayerLayerView did dealloc")
    }
    
    
    // MARK: - layoutSubviews
    override open func layoutSubviews() {
        super.layoutSubviews()
        switch self.aspectRatio {
        case .default:
            self.playerLayer?.videoGravity = "AVLayerVideoGravityResizeAspect"
            self.playerLayer?.frame  = self.bounds
            break
        case .sixteen2NINE:
            self.playerLayer?.videoGravity = "AVLayerVideoGravityResize"
            self.playerLayer?.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: self.bounds.width/(16/9))
            break
        case .four2THREE:
            self.playerLayer?.videoGravity = "AVLayerVideoGravityResize"
            let _w = self.bounds.height * 4 / 3
            self.playerLayer?.frame = CGRect(x: (self.bounds.width - _w )/2, y: 0, width: _w, height: self.bounds.height)
            break
        }
        
        //        self.playerLayer?.frame  = CGRectMake(0, 0, 200, 200)
    }
    
    open func resetPlayer() {
        // 初始化状态变量
        self.playDidEnd = false
        self.playerItem = nil
        self.seekTime   = 0
        
        self.timer?.invalidate()
        
        self.pause()
        // 移除原来的layer
        self.playerLayer?.removeFromSuperlayer()
        // 替换PlayerItem为nil
        self.player?.replaceCurrentItem(with: nil)
        // 把player置为nil
        self.player = nil
    }
    
    open func prepareToDeinit() {
        self.timer?.invalidate()
        player?.removeObserver(self, forKeyPath: "rate")
        if let ob = timeObserver {
            player?.removeTimeObserver(ob)
            timeObserver = nil
        }
        self.playerItem = nil
        self.resetPlayer()
    }
    
    open func onTimeSliderBegan() {
        if self.player?.currentItem?.status == AVPlayerItemStatus.readyToPlay {
            self.timer?.fireDate = Date.distantFuture
        }
    }
    
    open func seekToTime(_ secounds: TimeInterval, completionHandler:(()->Void)?) {
        if secounds.isNaN {
            return
        }
        if self.player?.currentItem?.status == AVPlayerItemStatus.readyToPlay {
            let draggedTime = CMTimeMake(Int64(secounds), 1)
            self.player!.seek(to: draggedTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: { (finished) in
                completionHandler?()
//                if self.playerItem?.isPlaybackLikelyToKeepUp ?? false {
//                    self.state = .buffering
//                }
            })
        }
    }
    
    
    // MARK: - 设置视频URL
    fileprivate func onSetVideoURL() {
        self.repeatToPlay = false
        self.playDidEnd   = false
        self.configPlayer()
        
    }
    
    fileprivate func onPlayerItemChange() {
        if lastPlayerItem == playerItem {
            return
        }
        
        if let item = lastPlayerItem {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
            item.removeObserver(self, forKeyPath: "status")
            item.removeObserver(self, forKeyPath: "loadedTimeRanges")
            item.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
            item.removeObserver(self, forKeyPath: "playbackBufferFull")
        }
        
        lastPlayerItem = playerItem
        
        if let item = playerItem {
            NotificationCenter.default.addObserver(self, selector: #selector(self.moviePlayDidEnd(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem)
            
            item.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
            item.addObserver(self, forKeyPath: "loadedTimeRanges", options: NSKeyValueObservingOptions.new, context: nil)
            // 缓冲区空了，需要等待数据
            item.addObserver(self, forKeyPath: "playbackBufferEmpty", options: NSKeyValueObservingOptions.new, context: nil)
            // 缓冲区有足够数据可以播放了
            item.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: NSKeyValueObservingOptions.new, context: nil)
            
            item.addObserver(self, forKeyPath: "playbackBufferFull", options: NSKeyValueObservingOptions.new, context: nil)
        }
    }
    
    fileprivate func configPlayer(){
//
        self.playerItem = AVPlayerItem(url: videoURL)
        
        self.player     = AVPlayer(playerItem: playerItem!)
        
        self.player!.addObserver(self, forKeyPath: "rate", options: NSKeyValueObservingOptions.new, context: nil)
        
        self.playerLayer = AVPlayerLayer(player: player)
        
        self.playerLayer!.videoGravity = videoGravity
        
        self.layer.insertSublayer(playerLayer!, at: 0)
        
        self.timer  = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(playerTimerAction), userInfo: nil, repeats: true)
        
        RunLoop.current.add(self.timer!, forMode: RunLoopMode.commonModes)
        
//        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 1), queue: DispatchQueue.main, using: {
//            [weak self] (cmTime) in
//            guard let slf = self else {return}
//            if let playerItem = slf.playerItem {
//                if playerItem.duration.timescale != 0 {
//                    //                        let currentTime = CMTimeGetSeconds(slf.player!.currentTime())
//                    let time = TimeInterval(CMTimeGetSeconds(cmTime))
//                    let totalTime   = TimeInterval(playerItem.duration.value) / TimeInterval(playerItem.duration.timescale)
//                    slf.delegate?.bmPlayer(player: slf, playTimeDidChange: time, totalTime: totalTime)
//                }
//            }
//        })
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    
    // MARK: - 计时器事件
    @objc fileprivate func playerTimerAction() {
        
        if let playerItem = playerItem {
            if playerItem.duration.timescale != 0 {
                let currentTime = CMTimeGetSeconds(self.player!.currentTime())
                let totalTime   = TimeInterval(playerItem.duration.value) / TimeInterval(playerItem.duration.timescale)
                delegate?.bmPlayer(player: self, playTimeDidChange: currentTime, totalTime: totalTime)
                
//                print("currentTime: \(currentTime)")
//                print("status: \(playerItem.status == AVPlayerItemStatus.readyToPlay)")
//                print("playbackBufferEmpty: \(playerItem.isPlaybackBufferEmpty)")
//                print("playbackLikelyToKeepUp: \(playerItem.isPlaybackLikelyToKeepUp)")
//                print("playbackBufferFull: \(playerItem.isPlaybackBufferFull)")
            }
            //            updateStatus()
        }
    }
    
    fileprivate func updateStatus() {
        
        if let player = player {
            
            //            if playerItem!.isPlaybackLikelyToKeepUp || playerItem!.isPlaybackBufferFull {
            //                self.state = .bufferFinished
            //            } else {
            //                self.state = .buffering
            //            }
            
            if player.rate == 1 {
               delegate?.bmPlayer(player: self, playerIsPlaying: true)
            }else if player.rate == 0{
                delegate?.bmPlayer(player: self, playerIsPlaying: false)
            }else {
                self.state = .error
                delegate?.bmPlayer(player: self, playerIsPlaying: false)
            }
            
//            if player.error != nil {
//                self.state = .error
//                return
//            }
//            
//            if let currentItem = player.currentItem {
//                
//                if player.currentTime() >= currentItem.duration {
//                    if self.state != .playedToTheEnd {
//                        self.state = .playedToTheEnd
//                    }
//                }
//            }
            
//            if player.rate == 0.0 {
//                if player.error != nil {
//                    self.state = .error
//                    return
//                }
//                
//                if let currentItem = player.currentItem {
//                    
//                    if player.currentTime() >= currentItem.duration {
//                        if self.state != .playedToTheEnd {
//                            self.state = .playedToTheEnd
//                        }
//                        //                        return
//                    }
//                    
//                    //                    if currentItem.isPlaybackLikelyToKeepUp || currentItem.isPlaybackBufferFull {
//                    //
//                    //                    }
//                    
//                }
//                delegate?.bmPlayer(player: self, playerIsPlaying: false)
//            } else {
//                delegate?.bmPlayer(player: self, playerIsPlaying: true)
//            }
        }
    }
    
    // MARK: - Notification Event
    @objc fileprivate func moviePlayDidEnd(_ notif: Notification) {
        if state != .playedToTheEnd {
            self.state = .playedToTheEnd
            self.playDidEnd = true
        }
    }
    
    var active = true
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NSNotification.Name.UIApplicationDidEnterBackground.rawValue), object: nil, queue: nil) { [weak self](notification) in
            guard self != nil else { return }
            self!.active = true
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NSNotification.Name.UIApplicationWillEnterForeground.rawValue), object: nil, queue: nil) { [weak self](notification) in
            guard self != nil else { return }
            self!.active = false
        }
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - KVO
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if !active {return}
        if !isPlaying {return}
        guard let keyPath = keyPath else {return}
        if let item = object as? AVPlayerItem {
            
            if item == self.playerItem {
                
                if keyPath == "status" {
                    if item.status == AVPlayerItemStatus.readyToPlay {
                        self.state = .readyToPlay
                        print("status: readyToPlay")
                        play()
                    }else if item.status == AVPlayerItemStatus.failed {
                        self.state = .error
                        print("status: failed")
                    }else {
                        print("status: unKnow")
                    }
                }
                
                if item.status == AVPlayerItemStatus.readyToPlay {
                    
                    switch keyPath {
                    case "loadedTimeRanges":
                        // 计算缓冲进度,有缓冲进度不一定能播放
                        if let timeInterVarl    = self.availableDuration() {
                            
                            let duration        = item.duration
                            let totalDuration   = CMTimeGetSeconds(duration)
                            delegate?.bmPlayer(player: self, loadedTimeDidChange: timeInterVarl, totalDuration: totalDuration)
//                            print("loadedTimeRanges: \(timeInterVarl)")
                        }
                        
                    case "playbackBufferEmpty":
                        
//                        print("playbackBufferEmpty: \(self.playerItem!.isPlaybackBufferEmpty)")
                        // 当缓冲是空的时候
                        if self.playerItem!.isPlaybackBufferEmpty {
                            self.state = .buffering
                            self.bufferingSomeSecond()
                            //                        self.timer?.fireDate = Date.distantFuture
//                            print("playbackBufferEmpty")
                        }
                    case "playbackLikelyToKeepUp":
                        // 播放还是主要看playbackLikelyToKeepUp 是否为true,只要进了playbackBufferEmpty 为true,那么一定有playbackLikelyToKeepUp为true,开始播放
                        // 但是第一次播放时,可能没有进playbackBufferEmpty,也没有playbackLikelyToKeepUp
//                        print("playbackLikelyToKeepUp: \(self.playerItem!.isPlaybackLikelyToKeepUp)")
                        if self.playerItem!.isPlaybackLikelyToKeepUp {
                            self.state = .bufferFinished
                            //                        if state != .bufferFinished {
                            //                            //                            self.playDidEnd = true
//                            print("playbackLikelyToKeepUp")
                            //                        }
                        }else {
                            self.state = .buffering
                        }
                        
                    case "playbackBufferFull":
                        // 播放还是主要看playbackLikelyToKeepUp 是否为true,只要进了playbackBufferEmpty 为true,那么一定有playbackLikelyToKeepUp为true,开始播放
                        // 但是第一次播放时,可能没有进playbackBufferEmpty,也没有playbackLikelyToKeepUp
//                        print("playbackBufferFull: \(self.playerItem!.isPlaybackBufferFull)")
                        if self.playerItem!.isPlaybackBufferFull {
                            self.state = .bufferFinished
                            //                        if state != .bufferFinished {
                            //                            //                            self.playDidEnd = true
//                            print("isPlaybackBufferFull")
                            //                        }
                        }
                    default:
                        break
                    }
                }
            }
        }else if let player = self.player {
            if keyPath == "rate" {
                print("rate: \(player.rate)")
                updateStatus()
            }
        }
        
        //        if player == object as? AVPlayer, let p = player {
        //            updateStatus()
        //        }
    }
    
    /**
     缓冲进度
     
     - returns: 缓冲进度
     */
    var lastBufferPauseTime:TimeInterval = 0
    fileprivate func availableDuration() -> TimeInterval? {
        if let loadedTimeRanges = player?.currentItem?.loadedTimeRanges,
            let first = loadedTimeRanges.first {
            let timeRange = first.timeRangeValue
            // startSeconds 是本次缓冲为空的时间,也就是此次播放暂停的时间
            let startSeconds = CMTimeGetSeconds(timeRange.start)
            // 从startSeconds开始缓冲了多少时间
            let durationSecound = CMTimeGetSeconds(timeRange.duration)
//            print("startSeconds: \(startSeconds)")
//            print("durationSecound: \(durationSecound)")
//            
            let result = startSeconds + durationSecound
//            if durationSecound <= 1 && lastBufferPauseTime != (currentTime + durationSecound) {
//                lastBufferPauseTime = currentTime
//                seekToTime(currentTime + durationSecound, completionHandler: {
//                    self.play()
//                })
//            }
            return result
        }
        return nil
    }
    
    /**
     缓冲比较差的时候
     */
    fileprivate func bufferingSomeSecond() {
        self.state = .buffering
        // playbackBufferEmpty会反复进入，因此在bufferingOneSecond延时播放执行完之前再调用bufferingSomeSecond都忽略
        
        if isBuffering {
            return
        }
        isBuffering = true
        // 需要先暂停一小会之后再播放，否则网络状况不好的时候时间在走，声音播放不出来
        pause()
        
        let popTime = DispatchTime.now() + Double(Int64( Double(NSEC_PER_SEC) * 2.0 )) / Double(NSEC_PER_SEC)
        
        DispatchQueue.main.asyncAfter(deadline: popTime) {
            
//            self.play()
            // 如果执行了play还是没有播放则说明还没有缓存好，则再次缓存一段时间
            self.isBuffering = false
            if let item = self.playerItem {
                if !item.isPlaybackLikelyToKeepUp {
                    self.bufferingSomeSecond()
                }
//                else {
//                    // 如果此时用户已经暂停了，则不再需要开启播放了
//                    self.state = BMPlayerState.bufferFinished
//                }
            }
        }
    }
}
