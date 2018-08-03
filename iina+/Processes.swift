//
//  YouGet.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal
import SwiftHTTP

class Processes: NSObject {
    
    static let shared = Processes()
    
    fileprivate override init() {
    }
    
    func which(_ str: String) -> [String] {
        // which you-get
        // command -v you-get
        // type -P you-get
        
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launchPath = "/bin/bash"
        task.arguments  = ["-l", "-c", "which \(str)"]
        
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output.components(separatedBy: "\n").filter({ $0 != "" })
        }
        return []
    }

    var decodeTask: Process?
    func decodeURL(_ url: String,
                   _ block: @escaping (_ youget: YouGetJSON) -> Void,
                   _ error: @escaping (_ error: Error) -> Void) {
        if let task = decodeTask, task.isRunning {
            decodeTask?.suspend()
            decodeTask?.terminate()
            decodeTask?.waitUntilExit()
            decodeTask = nil
        }
        
        decodeTask = Process()
        let pipe = Pipe()

        decodeTask?.standardOutput = pipe
        decodeTask?.launchPath = which(Preferences.shared.liveDecoder.rawValue).first ?? ""
        decodeTask?.arguments  = ["--json", url]
        decodeTask?.launch()
        
        decodeTask?.terminationHandler = { _ in
            guard self.decodeTask?.terminationReason != .uncaughtSignal else {
                return
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            do {
                let json = try JSONParser.JSONObjectWithData(data)
                let re = try YouGetJSON(object: json)
                block(re)
            } catch let er {
                error(er)
                print("json error: \(er)")
                if let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            }
        }
    }
    
    func openWithPlayer(_ url: String, title: String) {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        var mpvArgs = ["\(MPVOption.Miscellaneous.forceMediaTitle)=\(title)"]
        
        if url.contains("douyu") {
            mpvArgs.append(contentsOf: [MPVOption.Network.cookies,
                                        "\(MPVOption.Network.cookiesFile)=\(getCookies(for: .douyu))"])
        }
        
        switch Preferences.shared.livePlayer {
        case .iina:
            task.launchPath = Preferences.shared.livePlayer.rawValue
            mpvArgs = mpvArgs.map {
                "--mpv-" + $0
            }
        case .mpv:
            task.launchPath = which(Preferences.shared.livePlayer.rawValue).first ?? ""
            mpvArgs.append(MPVOption.Terminal.quiet)
            mpvArgs = mpvArgs.map {
                "--" + $0
            }
        }
        mpvArgs.append(url)
        task.arguments = mpvArgs
        task.launch()
        
    }
    

}

private extension Processes {
    
    func getCookies(for website: LiveSupportList) -> String {
        switch website {
        case .douyu:
            let douyuCookie = "https://passport.douyu.com/lapi/did/api/get"
            let time = UInt32(NSDate().timeIntervalSinceReferenceDate)
            srand48(Int(time))
            let random = "\(drand48())"
            let parameters = ["client_id": "1",
                              "callback": ("jsonp_" + random).replacingOccurrences(of: ".", with: "")]
            let headers = ["Referer": "http://www.douyu.com"]
            
            let httpSemaphore = DispatchSemaphore(value: 0)
            var cookiesString = ""
            
            HTTP.GET(douyuCookie, parameters: parameters, headers: headers) { response in
                do {
                    var str = response.text
                    str = str?.subString(from: "(", to: ")")
                    let json = try JSONParser.JSONObjectWithData(str?.data(using: .utf8) ?? Data())
                    let didStr: String = try json.value(for: "data.did")
                    cookiesString = """
                    ..douyu.com    TRUE    /    FALSE    1535865698    dy_did    \(didStr)
                    .www.douyu.com    TRUE    /    FALSE    1535865771    acf_did    \(didStr)
                    """
                } catch let error {
                    print(error)
                }
                httpSemaphore.signal()
            }
            httpSemaphore.wait()
            return cookiesString
        default:
            return ""
        }
    }
}
