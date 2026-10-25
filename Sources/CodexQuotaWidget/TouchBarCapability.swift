import IOKit

/// 通过 IOKit 判断当前机器是否真的带 Touch Bar，避免在没有该硬件的 Mac 上显示无用菜单项。
enum TouchBarCapability {
    static let isAvailable: Bool = {
        guard let matching = IOServiceMatching("AppleMultitouchTouchBar") else {
            return false
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            return false
        }
        IOObjectRelease(service)
        return true
    }()
}
