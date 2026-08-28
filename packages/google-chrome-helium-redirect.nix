{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "google-chrome-helium-redirect";
  version = "1.0.0";

  dontUnpack = true;
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    cat > google-chrome-helium-redirect.m <<'OBJC'
    #import <Cocoa/Cocoa.h>
    #import <Carbon/Carbon.h>

    static NSString *const HeliumBundleIdentifier = @"net.imput.helium";
    static NSString *const HeliumExecutable = @"/Applications/Helium.app/Contents/MacOS/Helium";

    @interface ChromeToHeliumRedirectDelegate : NSObject <NSApplicationDelegate>
    @property(nonatomic) BOOL forwardedRequest;
    @end

    @implementation ChromeToHeliumRedirectDelegate

    - (void)applicationWillFinishLaunching:(NSNotification *)notification {
      [[NSAppleEventManager sharedAppleEventManager]
          setEventHandler:self
              andSelector:@selector(handleOpenUrlEvent:withReplyEvent:)
            forEventClass:kInternetEventClass
               andEventID:kAEGetURL];
    }

    - (void)applicationDidFinishLaunching:(NSNotification *)notification {
      NSArray<NSString *> *processArguments = NSProcessInfo.processInfo.arguments;
      NSMutableArray<NSString *> *heliumArguments = [NSMutableArray array];

      for (NSUInteger index = 1; index < processArguments.count; index++) {
        NSString *argument = processArguments[index];
        if (![argument hasPrefix:@"-psn_"]) {
          [heliumArguments addObject:argument];
        }
      }

      if (heliumArguments.count > 0) {
        [self launchHeliumExecutableWithArguments:heliumArguments];
        return;
      }

      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
          dispatch_get_main_queue(), ^{
            if (!self.forwardedRequest) {
              [self openHeliumTargets:@[]];
            }
          });
    }

    - (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames {
      [self openHeliumTargets:filenames];
      [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    }

    - (void)handleOpenUrlEvent:(NSAppleEventDescriptor *)event
                withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
      NSString *url = [event paramDescriptorForKeyword:keyDirectObject].stringValue;
      if (url.length > 0) {
        [self openHeliumTargets:@[url]];
      } else {
        [self openHeliumTargets:@[]];
      }
    }

    - (void)launchHeliumExecutableWithArguments:(NSArray<NSString *> *)arguments {
      self.forwardedRequest = YES;

      NSTask *task = [[NSTask alloc] init];
      task.executableURL = [NSURL fileURLWithPath:HeliumExecutable];
      task.arguments = arguments;

      NSError *error = nil;
      if (![task launchAndReturnError:&error]) {
        NSLog(@"Google Chrome to Helium redirect failed: %@", error.localizedDescription);
      }

      [NSApp terminate:nil];
    }

    - (void)openHeliumTargets:(NSArray<NSString *> *)targets {
      self.forwardedRequest = YES;

      NSMutableArray<NSString *> *arguments =
          [NSMutableArray arrayWithObjects:@"-b", HeliumBundleIdentifier, nil];
      [arguments addObjectsFromArray:targets];

      NSTask *task = [[NSTask alloc] init];
      task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
      task.arguments = arguments;

      NSError *error = nil;
      if (![task launchAndReturnError:&error]) {
        NSLog(@"Google Chrome to Helium redirect failed: %@", error.localizedDescription);
      }

      [NSApp terminate:nil];
    }

    @end

    int main(void) {
      @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        ChromeToHeliumRedirectDelegate *delegate =
            [[ChromeToHeliumRedirectDelegate alloc] init];
        application.delegate = delegate;
        [application run];
      }
      return 0;
    }
    OBJC

    $CC \
      -fobjc-arc \
      -Wall \
      -Wextra \
      -Werror \
      -framework Cocoa \
      -framework Carbon \
      google-chrome-helium-redirect.m \
      -o google-chrome-helium-redirect

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app="$out/Applications/Google Chrome.app"
    /bin/mkdir -p "$app/Contents/MacOS"
    /bin/cp google-chrome-helium-redirect "$app/Contents/MacOS/Google Chrome"

    /bin/cat > "$app/Contents/Info.plist" <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDisplayName</key>
      <string>Google Chrome</string>
      <key>CFBundleExecutable</key>
      <string>Google Chrome</string>
      <key>CFBundleIdentifier</key>
      <string>com.google.Chrome</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>Google Chrome</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>CFBundleURLTypes</key>
      <array>
        <dict>
          <key>CFBundleTypeRole</key>
          <string>Viewer</string>
          <key>CFBundleURLName</key>
          <string>Web URL</string>
          <key>CFBundleURLSchemes</key>
          <array>
            <string>http</string>
            <string>https</string>
          </array>
        </dict>
      </array>
      <key>LSMinimumSystemVersion</key>
      <string>14.0</string>
      <key>LSUIElement</key>
      <true/>
      <key>NSHighResolutionCapable</key>
      <true/>
    </dict>
    </plist>
    PLIST

    /usr/bin/codesign --force --sign - --identifier com.google.Chrome "$app"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    /usr/bin/plutil -lint "$out/Applications/Google Chrome.app/Contents/Info.plist"
    /usr/bin/codesign --verify --strict "$out/Applications/Google Chrome.app"
  '';

  meta = {
    description = "Compatibility app that redirects Google Chrome launches to Helium";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
