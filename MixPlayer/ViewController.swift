//
//  ViewController.swift
//  MixPlayer
//
//  Created by go.yaro on 10/6/16.
//  Copyright © 2016 DDDrop. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        if let url = NSURL(string: "https://d1hd0ww6piyb43.cloudfront.net/hls/andagi_652.m3u8") {
            view.addSubview(MixPlayer(url: url))
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }


}

