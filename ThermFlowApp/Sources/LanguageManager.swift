import SwiftUI

/// LanguageManager - Dual language localization support for CoolCumber V3
/// Supports automatic matching of system locale and seamless in-app runtime toggling.
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @Published var currentLanguage: String = "en"
    
    init() {
        let localeLang = Locale.current.language.languageCode?.identifier ?? "en"
        let saved = UserDefaults.standard.string(forKey: "app_language")
        self.currentLanguage = saved ?? (localeLang.contains("zh") ? "zh" : "en")
    }
    
    func setLanguage(_ lang: String) {
        currentLanguage = lang
        UserDefaults.standard.set(lang, forKey: "app_language")
    }
    
    func tr(_ key: String) -> String {
        let dict: [String: [String: String]] = [
            // Sidebar
            "status_center": ["en": "Status Center", "zh": "控制中心"],
            "thermal_power": ["en": "Thermal & Power", "zh": "能效与散热"],
            "system_optimizer": ["en": "System Optimizer", "zh": "系统优化"],
            "preferences": ["en": "Preferences", "zh": "偏好设置"],
            "quit_app": ["en": "Quit App", "zh": "退出应用"],
            "privacy": ["en": "Privacy Policy", "zh": "隐私政策"],
            "about_us": ["en": "About Us", "zh": "关于我们"],
            "version": ["en": "Version", "zh": "版本号"],
            "language": ["en": "Language", "zh": "显示语言"],
            
            // Status Center
            "ai_copilot_status": ["en": "AI Copilot status: %@", "zh": "AI 协作者状态: %@"],
            "system_is_healthy": ["en": "System is healthy. CPU at %@ and Memory at %@.", "zh": "系统状态健康。CPU %@，内存 %@。"],
            "ask_ai": ["en": "Ask AI", "zh": "咨询 AI"],
            "cpu_temp": ["en": "CPU Temp", "zh": "CPU 温度"],
            "fan_speed": ["en": "Fan Speed", "zh": "风扇转速"],
            "memory": ["en": "Memory", "zh": "内存占用"],
            "network_down": ["en": "Network Down", "zh": "网络下载"],
            "free_storage": ["en": "Free Storage", "zh": "可用空间"],
            "disk_used": ["en": "Disk Used", "zh": "磁盘占用"],
            "cpu_thermal_history": ["en": "CPU Thermal History", "zh": "CPU 温度历史轨迹"],
            "smart_clean": ["en": "Smart Clean", "zh": "智能释放"],
            "purge_inactive_ram": ["en": "Purge Inactive RAM", "zh": "释放闲置运行内存"],
            "max_cooling": ["en": "Max Cooling", "zh": "强力散热"],
            "force_100_fan": ["en": "Force 100% Fan Speed", "zh": "强制风扇 100% 运转"],
            "eco_mode": ["en": "Eco Mode", "zh": "环保限能"],
            "limit_cpu_power": ["en": "Limit CPU/GPU Power", "zh": "限制处理器最高功耗"],
            
            // Thermal & Power Hub
            "thermal_power_hub": ["en": "Thermal & Power Hub", "zh": "能效与散热中心"],
            "manage_cooling": ["en": "Manage cooling profiles, battery limits, and freeze background apps.", "zh": "管理散热模式、电池寿命限制以及冻结后台进程。"],
            "proactive_cooling": ["en": "Proactive Cooling Profile", "zh": "智能主动散热模式"],
            "fan_profile_desc": ["en": "System dynamic fan override controller.", "zh": "系统动态风扇速率智能覆盖控制。"],
            "eco": ["en": "Eco (Quiet)", "zh": "节能 (静音)"],
            "normal": ["en": "Normal (Auto)", "zh": "标准 (自动)"],
            "boost": ["en": "Boost (Performance)", "zh": "增压 (高性能)"],
            "manual_fan": ["en": "Manual Fan Override", "zh": "手动风扇速率干预"],
            "override_fan_speed": ["en": "Override fan speed limit manually.", "zh": "手动锁定覆盖系统预设的风扇转速。"],
            "battery_mgmt": ["en": "Battery Management & Health", "zh": "电池健康与充放电管理"],
            "smc_limit": ["en": "SMC Battery Charge Limit", "zh": "SMC 电池智能充电上限限制"],
            "limit_to": ["en": "Limit charging to %d%% to preserve health.", "zh": "锁定最高充电至 %d%% 以延长电池寿命。"],
            "lifespan_forecaster": ["en": "AI Battery Lifespan Forecaster", "zh": "AI 电池寿命衰减轨迹预测"],
            "future_health": ["en": "Future battery health based on limit.", "zh": "基于当前充电上限预测的未来电池健康走势。"],
            "years_1": ["en": "1 Year", "zh": "1 年后"],
            "years_2": ["en": "2 Years", "zh": "2 年后"],
            "forecaster_desc": ["en": "Forecast is calculated based on SMC charge limit profile and cycle count.", "zh": "预测曲线基于当前 SMC 限制设定与循环次数综合估算。"],
            "app_freezer": ["en": "App Freezer (Compressor)", "zh": "App 智能冷冻舱 (压缩器)"],
            "freeze_desc": ["en": "Temporarily suspend resource-heavy background processes via SIGSTOP.", "zh": "通过 SIGSTOP 信号对高功耗后台进程实施深冻，释放算力。"],
            "suspend": ["en": "Suspend", "zh": "深冻冻结"],
            "resume": ["en": "Resume", "zh": "解冻恢复"],
            
            // System Optimizer
            "system_optimizer_title": ["en": "System Optimizer", "zh": "深度系统优化管家"],
            "scan_desc": ["en": "Analyze diagnostic cache, background agents, and flush system settings.", "zh": "一键扫描系统诊断缓存、第三方后台常驻项并运行高级维护。"],
            "scanning": ["en": "Scanning Cache Folders & Rogue Agents...", "zh": "系统诊断与缓存垃圾深度扫描中..."],
            "scan_progress": ["en": "Inspecting LaunchAgents, Daemons, and developer trash caches.", "zh": "正在安全检索自启动项、后台服务以及开发者产生的临时文件。"],
            "developer_caches": ["en": "Developer Caches & Temp Files", "zh": "开发者缓存与临时垃圾文件"],
            "cache_desc": ["en": "Select cache directories to wipe out to reclaim precious SSD space.", "zh": "选中您想要安全擦除的缓存目录，以腾出 SSD 存储空间。"],
            "clean_selected": ["en": "Clean Selected", "zh": "清理选中项"],
            "space_clean": ["en": "Space Clean", "zh": "空间清理"],
            "running_processes": ["en": "Running Processes", "zh": "运行中进程"],
            "rogue_agents": ["en": "Rogue & Agents", "zh": "流氓常驻软件"],
            "maintenance": ["en": "Maintenance", "zh": "系统维护"],
            "re_scan": ["en": "Re-Scan System", "zh": "重新扫描"],
            "space_clean_done": ["en": "Your system space is clean!", "zh": "您的系统空间非常整洁！"],
            "process_ai": ["en": "Process Inspector & AI Explainer", "zh": "进程透视与 AI 意图解析"],
            "process_desc": ["en": "Identify CPU/Memory heavy tasks and ask AI for detailed origin explanations.", "zh": "精准定位占用异常的进程，一键咨询 AI 解析其背景和安全级别。"],
            "ai_banner": ["en": "AI diagnostics will decipher helper tasks instantly.", "zh": "AI 诊断将实时分析第三方常驻守护进程的安全意图。"],
            "rogue_title": ["en": "Rogue Software & Background Agents", "zh": "流氓常驻软件与后台自启项"],
            "rogue_desc": ["en": "Scan and disable third-party launch agents and persistent background daemons.", "zh": "扫描并卸载在开机时静默启动或后台常驻的第三方代理与守护进程。"],
            "no_rogue": ["en": "No rogue autostart agents found!", "zh": "未发现任何恶意的第三方自启常驻项！"],
            "uninstall": ["en": "Uninstall", "zh": "彻底卸载"],
            "maintenance_title": ["en": "System Maintenance Commands", "zh": "高级系统维护与脚本干预"],
            "maintenance_desc": ["en": "Rebuild indices, refresh configurations, or flush cache structures.", "zh": "重建系统索引、刷新全局配置、清理底层的网络和缓存结构。"],
            "rebuild_spotlight": ["en": "Rebuild Spotlight Index", "zh": "重建 Spotlight 全局索引"],
            "spotlight_desc": ["en": "Forces macOS metadata server mdutil to reindex the system disk.", "zh": "强制 macOS 元数据服务器 mdutil 深度重新检索并建立全盘索引。"],
            "flush_dns": ["en": "Flush DNS Cache", "zh": "清空 DNS 解析缓存"],
            "dns_desc": ["en": "Flushes mDNSResponder configuration to resolve domain connection issues.", "zh": "重载 mDNSResponder 服务，解决第三方网站连接缓慢或污染。"],
            "purge_ram": ["en": "Purge System RAM", "zh": "深度释放系统物理内存"],
            "ram_desc": ["en": "Trigger kernel memory pressure warning to force cache compression.", "zh": "向内核发送虚拟内存收紧压力信号，强制系统整理闲置页。"],
            "run": ["en": "Run", "zh": "立即执行"],
            
            // Preferences
            "pref_title": ["en": "Configuration Preferences", "zh": "全局偏好设置"],
            "pref_desc": ["en": "Manage API credentials and LLM providers for the diagnostic copilot.", "zh": "配置用于 AI 诊断和能效分析的 LLM 模型服务秘钥。"],
            "ai_credentials": ["en": "Diagnostic Copilot Credentials", "zh": "AI 协作者模型服务凭证"],
            "ai_provider": ["en": "AI Model Provider", "zh": "AI 大模型提供商"],
            "api_key": ["en": "API Access Key", "zh": "API 访问密钥"],
            "save_key": ["en": "Save API Key", "zh": "保存密钥配置"],
            
            // New Additions
            "scan_system": ["en": "Scan System", "zh": "扫描系统"],
            "clean_cache_title": ["en": "Clean System Cache?", "zh": "清理系统缓存？"],
            "clean_cache_msg": ["en": "Are you sure you want to move the selected cache folders to the Trash?", "zh": "确定要将所选缓存文件夹移至废纸篓吗？"],
            "clean_trash": ["en": "Clean Trash", "zh": "清理缓存"],
            "cancel": ["en": "Cancel", "zh": "取消"],
            "force_kill_title": ["en": "Force Terminate Process?", "zh": "强制结束进程？"],
            "force_kill_msg": ["en": "Are you sure you want to kill '%@' (PID: %d)?", "zh": "确定要强制结束进程 '%@' (PID: %d) 吗？"],
            "kill_process": ["en": "Kill Process", "zh": "结束进程"],
            "uninstall_service_title": ["en": "Uninstall Launch Service?", "zh": "卸载自启服务？"],
            "uninstall_service_msg": ["en": "Do you want to permanently disable and delete '%@'?", "zh": "确定要永久禁用并删除自启项 '%@' 吗？"],
            "ai_eval": ["en": "AI Evaluation:", "zh": "AI 分析评估："],
            "rebuild_success": ["en": "Spotlight Index rebuild triggered successfully.", "zh": "Spotlight 索引重建任务已成功触发。"],
            "dns_success": ["en": "DNS cache flushed.", "zh": "DNS 缓存已成功清空。"],
            "ram_success": ["en": "Memory purged successfully.", "zh": "内存已成功释放。"],
            "error_prefix": ["en": "Error: %@", "zh": "错误：%@"],
            "pid_label": ["en": "PID: %d", "zh": "进程 ID: %d"],
            "proactive_enabled": ["en": "Proactive Cooling Enabled", "zh": "智能主动散热模式已开启"],
            "proactive_disabled": ["en": "Proactive Cooling Disabled", "zh": "智能主动散热模式已关闭"],
            "fan_override_set": ["en": "Fan override set to %d RPM.", "zh": "风扇已强制覆盖锁定为 %d RPM。"],
            "smc_applied": ["en": "SMC Limit applied.", "zh": "SMC 充电限制已成功应用。"],
            "smc_failed": ["en": "Failed to set SMC charge limit", "zh": "设置 SMC 充电限制失败"],
            
            // Software Update
            "software_update": ["en": "Software Update", "zh": "软件在线更新"],
            "update_desc": ["en": "Check for the latest releases from GitHub directly.", "zh": "直接检测并获取来自 GitHub 的最新版本发布。"],
            "check_updates": ["en": "Check for Updates", "zh": "检查新版本"],
            "checking_updates": ["en": "Checking...", "zh": "正在检查..."],
            "current_version": ["en": "Current Version", "zh": "当前版本"],
            "new_version_available": ["en": "New Version Available", "zh": "发现可用新版本"],
            "auto_check": ["en": "Auto Check Updates", "zh": "启动时自动检测更新"],
            "update_now": ["en": "Update Now", "zh": "立即下载更新"],
            "downloading": ["en": "Downloading...", "zh": "正在下载..."],
            "view_on_github": ["en": "View on GitHub", "zh": "前往 GitHub 查看"]
        ]
        return dict[key]?[currentLanguage] ?? key
    }
}
