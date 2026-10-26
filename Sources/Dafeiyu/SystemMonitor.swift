import Foundation

/// CPU / 内存采样。CPU 用相邻两次 CPU tick 差值算占用率。
final class SystemMonitor {
    private var last: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let cur = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { last = cur }
        guard let prev = last else { return 0 }

        let user = Double(cur.user &- prev.user)
        let system = Double(cur.system &- prev.system)
        let idle = Double(cur.idle &- prev.idle)
        let nice = Double(cur.nice &- prev.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return (user + system + nice) / total * 100
    }

    func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let page = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * page
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(100, (active + wired + compressed) / total * 100)
    }
}
