import Foundation
import Combine

class LLMEngine: ObservableObject {
    static let shared = LLMEngine()
    
    @Published var isLoading = false
    @Published var responseText = ""
    
    func askAI(provider: String, completion: @escaping (String) -> Void) {
        guard let apiKey = KeychainHelper.shared.read(account: provider), !apiKey.isEmpty else {
            completion("Please configure your API Key in Settings first.")
            return
        }
        
        let endpoint = provider == "deepseek" 
            ? "https://api.deepseek.com/v1/chat/completions"
            : "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        
        let model = provider == "deepseek" ? "deepseek-chat" : "qwen-plus"
        
        let daemon = DaemonManager.shared
        
        // Fetch top processes
        daemon.readTopProcesses(count: 3) { processes in
            var processesStr = ""
            for p in processes {
                if let name = p["name"] as? String, let cpu = p["cpu"] as? Double {
                    processesStr += "- \(name): \(Int(cpu))% CPU\n"
                }
            }
            
            var metricLines: [String] = []
            if let cpuTemp = daemon.temperatures["CPU"] {
                metricLines.append("- CPU Temperature: \(Int(cpuTemp))°C")
            }
            if let fanRPM = Int(daemon.fanSpeed.replacingOccurrences(of: " RPM", with: "")), fanRPM > 0 {
                metricLines.append("- Fan Speed: \(fanRPM) RPM")
            }
            if let memTotal = daemon.memoryStats["total"],
               let memUsed = daemon.memoryStats["used"], memTotal > 0 {
                let memPercent = memUsed / memTotal * 100
                metricLines.append("- RAM Usage: \(Int(memPercent))%")
            }
            if let download = daemon.networkStats["download"] {
                metricLines.append("- Download Rate: \(String(format: "%.1f", download / 1024 / 1024)) MB/s")
            }
            if !processesStr.isEmpty {
                metricLines.append("- Top CPU-consuming process names:\n\(processesStr)")
            }
            guard !metricLines.isEmpty else {
                DispatchQueue.main.async {
                    let message = "No verified telemetry is available to analyze."
                    self.responseText = message
                    completion(message)
                }
                return
            }

            let systemStatus = "Current macOS System Metrics:\n" + metricLines.joined(separator: "\n")
            
            let systemPrompt = "You are a senior macOS systems engineer. Analyze the system metrics and provide a brief, professional explanation in 1-2 sentences of why the computer might be hot/slow and give action suggestions. Output in Chinese."
            
            let payload: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": systemStatus]
                ],
                "temperature": 0.5
            ]
            
            guard let url = URL(string: endpoint) else {
                DispatchQueue.main.async {
                    completion("Invalid API URL.")
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                DispatchQueue.main.async {
                    completion("Failed to serialize request.")
                }
                return
            }
            
            DispatchQueue.main.async {
                self.isLoading = true
                self.responseText = "Thinking..."
            }
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                if let error = error {
                    DispatchQueue.main.async {
                        completion("Connection Error: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        completion("Empty response from AI server.")
                    }
                    return
                }
                
                // Print response for debug
                if let rawJSON = try? JSONSerialization.jsonObject(with: data, options: []),
                   let dict = rawJSON as? [String: Any] {
                    
                    if let choices = dict["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        DispatchQueue.main.async {
                            self.responseText = content
                            completion(content)
                        }
                        return
                    } else if let errorObj = dict["error"] as? [String: Any],
                              let errMsg = errorObj["message"] as? String {
                        DispatchQueue.main.async {
                            completion("AI API Error: \(errMsg)")
                        }
                        return
                    }
                }
                
                DispatchQueue.main.async {
                    completion("Failed to parse AI response.")
                }
            }
            task.resume()
        }
    }
    
    func explainProcess(name: String, path _: String, completion: @escaping (String) -> Void) {
        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? "deepseek"
        guard let apiKey = KeychainHelper.shared.read(account: provider), !apiKey.isEmpty else {
            completion("请先在设置中配置 API Key。")
            return
        }
        
        let endpoint = provider == "deepseek" 
            ? "https://api.deepseek.com/v1/chat/completions"
            : "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        
        let model = provider == "deepseek" ? "deepseek-chat" : "qwen-plus"
        
        // Do not transmit the user's filesystem paths to third-party AI services.
        let userMessage = "进程名: \(name)"
        
        let systemPrompt = """
        你是一个资深的 macOS 系统工程师。解释这个进程是什么，属于哪个应用或系统组件，在 CPU/内存高负载时是否可以安全关闭，以及强制关闭它有什么风险或后果。用中文回答，内容限制在 3 句话内，清晰简洁。
        """
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.3
        ]
        
        guard let url = URL(string: endpoint) else {
            completion("API URL 格式错误。")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion("构建请求数据失败。")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion("连接失败: \(error.localizedDescription)")
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion("无响应数据。")
                }
                return
            }
            
            if let rawJSON = try? JSONSerialization.jsonObject(with: data, options: []),
               let dict = rawJSON as? [String: Any] {
                
                if let choices = dict["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    DispatchQueue.main.async {
                        completion(content)
                    }
                    return
                } else if let errorObj = dict["error"] as? [String: Any],
                          let errMsg = errorObj["message"] as? String {
                    DispatchQueue.main.async {
                        completion("AI API 错误: \(errMsg)")
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                completion("解析 AI 响应失败。")
            }
        }
        task.resume()
    }
}
