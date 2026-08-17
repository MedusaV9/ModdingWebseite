// goobykit — Godot-4-iOS-Plugin-Bootstrap (GOOBY-WIDGETS).
//
// Diese Datei ist die EINZIGE Quelle der statischen Bibliothek goobykit.a
// (gebaut von tools/ci/build_goobykit.sh, referenziert von goobykit.gdip).
// Der Godot-Exporter generiert im Xcode-Projekt einen Aufruf von
// goobykit_init() beim Engine-Start (godot_ios_plugins_initialize) —
// deshalb ObjC++ (.mm): das Symbol muss C++-gemangelt sein, exakt wie bei
// den offiziellen godot-ios-plugins.
//
// Bewusst OHNE Godot-Header: die Godot-Seite spricht ueber die Datei-Outbox
// Documents/goobykit/ (scripts/platform/goobykit_bridge.gd schreibt atomar),
// die eigentliche Arbeit (App-Group-Spiegel, WidgetCenter-Reload,
// ActivityKit-Live-Activities) macht die Swift-Klasse GoobyKitRuntime, die
// tools/ci/inject_widgets.rb ins App-Target injiziert. So braucht die CI
// keinen Godot-Quellbaum + SCons-Header-Generierung, und die Bruecke bleibt
// auf Linux headless komplett testbar.

#import <Foundation/Foundation.h>

void goobykit_init() {
	Class runtime = NSClassFromString(@"GoobyKitRuntime");
	if (runtime == nil) {
		NSLog(@"[goobykit] GoobyKitRuntime fehlt — Widget-Daemon inaktiv "
		      @"(tools/ci/inject_widgets.rb nicht gelaufen?)");
		return;
	}
	SEL start_selector = NSSelectorFromString(@"start");
	if (![runtime respondsToSelector:start_selector]) {
		NSLog(@"[goobykit] GoobyKitRuntime.start fehlt — Widget-Daemon inaktiv");
		return;
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[runtime performSelector:start_selector];
#pragma clang diagnostic pop
	NSLog(@"[goobykit] Widget-Daemon gestartet");
}

void goobykit_deinit() {
	Class runtime = NSClassFromString(@"GoobyKitRuntime");
	if (runtime == nil) {
		return;
	}
	SEL stop_selector = NSSelectorFromString(@"stop");
	if ([runtime respondsToSelector:stop_selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[runtime performSelector:stop_selector];
#pragma clang diagnostic pop
	}
}
