// nightshift: 命令行开关 macOS Night Shift
// 用法：nightshift on|off|status
// macOS 没有公开的 Night Shift API，这里通过 CoreBrightness 私有框架的
// CBBlueLightClient 实现；Hammerspoon 的 Lua 层无法直接调用 ObjC，所以编译成独立小工具。
// 首次加载时由 lib/night_shift.lua 自动编译，无需手动执行。

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef struct {
    BOOL active;
    BOOL enabled;
    BOOL sunSchedulePermitted;
    int mode;
    struct { int hour; int minute; } fromTime;
    struct { int hour; int minute; } toTime;
    int disableFlags;
} BlueLightStatus;

@interface CBBlueLightClient : NSObject
- (BOOL)setEnabled:(BOOL)enabled;
- (BOOL)getBlueLightStatus:(BlueLightStatus *)status;
@end

static CBBlueLightClient *blueLightClient(void) {
    static CBBlueLightClient *instance;
    if (instance) return instance;
    void *handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                          RTLD_LAZY);
    if (!handle) return nil;
    Class cls = NSClassFromString(@"CBBlueLightClient");
    if (!cls) return nil;
    instance = [[cls alloc] init];
    return instance;
}

static BOOL readEnabled(CBBlueLightClient *client) {
    BlueLightStatus status = {0};
    if ([client respondsToSelector:@selector(getBlueLightStatus:)]) {
        [client getBlueLightStatus:&status];
    }
    return status.enabled;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        CBBlueLightClient *client = blueLightClient();
        if (!client) {
            fprintf(stderr, "CoreBrightness unavailable\n");
            return 1;
        }

        if (argc != 2) {
            fprintf(stderr, "usage: nightshift on|off|status\n");
            return 2;
        }

        if (strcmp(argv[1], "status") == 0) {
            printf("%s\n", readEnabled(client) ? "on" : "off");
            return 0;
        }

        BOOL target;
        if (strcmp(argv[1], "on") == 0) {
            target = YES;
        } else if (strcmp(argv[1], "off") == 0) {
            target = NO;
        } else {
            fprintf(stderr, "usage: nightshift on|off|status\n");
            return 2;
        }

        [client setEnabled:target];
        BOOL actual = readEnabled(client);
        printf("%s\n", actual ? "on" : "off");
        return actual == target ? 0 : 1;
    }
}
